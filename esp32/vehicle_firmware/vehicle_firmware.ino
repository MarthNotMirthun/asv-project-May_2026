// ============================================================
// Module:      vehicle_firmware.ino
// Description: ASV catamaran vehicle micro-ROS node. Owns motor
//              control (L298N), MPU-6050 IMU, and JSN-SR04T sonar.
//              Subscribes /cmd_vel; publishes /imu/data, /wheel/velocity,
//              and /collision/range_cm. Enforces ESTOP, cmd watchdog,
//              and stall-current protection in the control loop.
// Target:      ESP32 #1 (vehicle), micro-ROS Arduino, ROS 2 Jazzy agent
// Pipeline:    Pi micro-ROS agent <-UART/USB-> THIS -> L298N / sensors
// Author:      fpga-verilog-engineer agent (firmware task)
// Date:        2026-06-29
// ============================================================
//
// CLAUDE.md contract:
//  - Subscribes /cmd_vel (Twist), RELIABLE QoS.
//  - Publishes /imu/data (Imu, 100Hz) BEST_EFFORT,
//              /wheel/velocity (TwistStamped, 50Hz) BEST_EFFORT,
//              /collision/range_cm (10Hz) BEST_EFFORT.
//  - micro-ROS agent link over Serial @ 115200.
//  - Safety overrides (ESTOP, watchdog, stall trip) run in loop(),
//    not only in the cmd_vel callback.
//
// micro-ROS Arduino library required (micro_ros_arduino). Transport
// defaults to serial; configure the agent on the Pi to match.
//
#include <micro_ros_arduino.h>

#include <stdio.h>
#include <rcl/rcl.h>
#include <rcl/error_handling.h>
#include <rclc/rclc.h>
#include <rclc/executor.h>

#include <geometry_msgs/msg/twist.h>
#include <geometry_msgs/msg/twist_stamped.h>
#include <sensor_msgs/msg/imu.h>
#include <std_msgs/msg/float32.h>

#include "motor_control.h"
#include "mpu6050_driver.h"
#include "sonar_driver.h"

// ---- Loop rate constants ----
#define IMU_PERIOD_MS     10    // 100Hz (CLAUDE.md)
#define WHEEL_PERIOD_MS   20    // 50Hz  (CLAUDE.md)
#define SONAR_PERIOD_MS   100   // 10Hz  (CLAUDE.md)
#define CONTROL_PERIOD_MS 10    // 100Hz motor/safety update

// ---- Wheel velocity estimation (CLAUDE.md placeholder) ----
#define WHEEL_MAX_SPEED_MS  0.5f   // m/s at full duty; CALIBRATE at pool test

// ---- micro-ROS entities ----
rcl_node_t        node;
rclc_support_t    support;
rcl_allocator_t   allocator;
rclc_executor_t   executor;

rcl_subscription_t sub_cmd_vel;
rcl_publisher_t    pub_imu;
rcl_publisher_t    pub_wheel;
rcl_publisher_t    pub_range;

geometry_msgs__msg__Twist        msg_cmd_vel;
sensor_msgs__msg__Imu            msg_imu;
geometry_msgs__msg__TwistStamped msg_wheel;
std_msgs__msg__Float32           msg_range;

// ---- Timing accumulators ----
uint32_t t_imu = 0, t_wheel = 0, t_sonar = 0, t_ctrl = 0;

#define RCCHECK(fn) { rcl_ret_t rc = (fn); if (rc != RCL_RET_OK) { error_loop(); } }
#define RCSOFT(fn)  { rcl_ret_t rc = (fn); (void)rc; }

// Fatal init failure: blink onboard LED forever (safe — motors stay at 0).
void error_loop() {
  pinMode(LED_BUILTIN, OUTPUT);
  while (1) {
    digitalWrite(LED_BUILTIN, !digitalRead(LED_BUILTIN));
    delay(120);
  }
}

// ---- cmd_vel callback: only updates the command, never drives PWM directly.
// Actual PWM application + all safety overrides happen in motor_update().
void cmd_vel_cb(const void *msgin) {
  const geometry_msgs__msg__Twist *m = (const geometry_msgs__msg__Twist *)msgin;
  motor_on_cmd_vel((float)m->linear.x, (float)m->angular.z);
}

// Fill the static parts of the IMU message once.
void imu_msg_init() {
  // frame_id = "imu_link"
  static char imu_frame[] = "imu_link";
  msg_imu.header.frame_id.data = imu_frame;
  msg_imu.header.frame_id.size = strlen(imu_frame);
  msg_imu.header.frame_id.capacity = sizeof(imu_frame);

  // Orientation not estimated on the MCU -> mark unknown per ROS convention:
  // orientation covariance[0] = -1 signals "no orientation".
  msg_imu.orientation.x = 0; msg_imu.orientation.y = 0;
  msg_imu.orientation.z = 0; msg_imu.orientation.w = 1;
  for (int i = 0; i < 9; i++) {
    msg_imu.orientation_covariance[i] = 0.0;
    msg_imu.angular_velocity_covariance[i] = 0.0;
    msg_imu.linear_acceleration_covariance[i] = 0.0;
  }
  // CLAUDE.md: covariances -1 (unknown) for bring-up.
  msg_imu.orientation_covariance[0] = -1.0;
  msg_imu.angular_velocity_covariance[0] = -1.0;
  msg_imu.linear_acceleration_covariance[0] = -1.0;
}

void wheel_msg_init() {
  static char wheel_frame[] = "base_link";
  msg_wheel.header.frame_id.data = wheel_frame;
  msg_wheel.header.frame_id.size = strlen(wheel_frame);
  msg_wheel.header.frame_id.capacity = sizeof(wheel_frame);
}

void setup() {
  // Drivers first so motors are guaranteed at 0 before anything else.
  motor_setup();
  sonar_setup();
  bool imu_ok = mpu_setup();
  (void)imu_ok;  // continue even if IMU absent; /imu/data will read zeros

  // micro-ROS transport over default Serial @ 115200 (CLAUDE.md).
  Serial.begin(115200);
  set_microros_transports();
  delay(2000);

  allocator = rcl_get_default_allocator();
  RCCHECK(rclc_support_init(&support, 0, NULL, &allocator));
  RCCHECK(rclc_node_init_default(&node, "asv_vehicle_node", "", &support));

  // Subscriber: /cmd_vel (RELIABLE — default reliable QoS).
  RCCHECK(rclc_subscription_init_default(
      &sub_cmd_vel, &node,
      ROSIDL_GET_MSG_TYPE_SUPPORT(geometry_msgs, msg, Twist),
      "/cmd_vel"));

  // Publishers: sensor streams use BEST_EFFORT (CLAUDE.md).
  RCCHECK(rclc_publisher_init_best_effort(
      &pub_imu, &node,
      ROSIDL_GET_MSG_TYPE_SUPPORT(sensor_msgs, msg, Imu),
      "/imu/data"));
  RCCHECK(rclc_publisher_init_best_effort(
      &pub_wheel, &node,
      ROSIDL_GET_MSG_TYPE_SUPPORT(geometry_msgs, msg, TwistStamped),
      "/wheel/velocity"));
  RCCHECK(rclc_publisher_init_best_effort(
      &pub_range, &node,
      ROSIDL_GET_MSG_TYPE_SUPPORT(std_msgs, msg, Float32),
      "/collision/range_cm"));

  // Executor with one subscription.
  RCCHECK(rclc_executor_init(&executor, &support.context, 1, &allocator));
  RCCHECK(rclc_executor_add_subscription(
      &executor, &sub_cmd_vel, &msg_cmd_vel, &cmd_vel_cb, ON_NEW_DATA));

  imu_msg_init();
  wheel_msg_init();

  uint32_t now = millis();
  t_imu = t_wheel = t_sonar = t_ctrl = now;
}

void loop() {
  uint32_t now = millis();

  // Service incoming /cmd_vel (non-blocking spin).
  RCSOFT(rclc_executor_spin_some(&executor, RCL_MS_TO_NS(1)));

  // --- Control + safety @ 100Hz: ESTOP, watchdog, stall trip, PWM apply ---
  if ((now - t_ctrl) >= CONTROL_PERIOD_MS) {
    t_ctrl = now;
    motor_set_estop(sonar_get_estop());  // latch latest ESTOP into motor logic
    motor_update();                      // applies all overrides + PWM
  }

  // --- IMU publish @ 100Hz ---
  if ((now - t_imu) >= IMU_PERIOD_MS) {
    t_imu = now;
    ImuSample s = mpu_read();
    msg_imu.header.stamp.sec     = (int32_t)(now / 1000);
    msg_imu.header.stamp.nanosec = (uint32_t)((now % 1000) * 1000000UL);
    msg_imu.angular_velocity.x = s.gx;
    msg_imu.angular_velocity.y = s.gy;
    msg_imu.angular_velocity.z = s.gz;
    msg_imu.linear_acceleration.x = s.ax;
    msg_imu.linear_acceleration.y = s.ay;
    msg_imu.linear_acceleration.z = s.az;
    RCSOFT(rcl_publish(&pub_imu, &msg_imu, NULL));
  }

  // --- Wheel velocity publish @ 50Hz (estimated from applied duty) ---
  if ((now - t_wheel) >= WHEEL_PERIOD_MS) {
    t_wheel = now;
    float lfrac = (float)motor_get_left_duty()  / (float)MOTOR_LEDC_MAX;
    float rfrac = (float)motor_get_right_duty() / (float)MOTOR_LEDC_MAX;
    float lvel  = lfrac * WHEEL_MAX_SPEED_MS * (motor_get_left_fwd()  ? 1.0f : -1.0f);
    float rvel  = rfrac * WHEEL_MAX_SPEED_MS * (motor_get_right_fwd() ? 1.0f : -1.0f);

    // Body-frame: linear.x = mean forward speed, angular.z ~ (R-L) differential.
    msg_wheel.header.stamp.sec     = (int32_t)(now / 1000);
    msg_wheel.header.stamp.nanosec = (uint32_t)((now % 1000) * 1000000UL);
    msg_wheel.twist.linear.x  = 0.5f * (lvel + rvel);
    msg_wheel.twist.angular.z = (rvel - lvel);  // scaled by track width downstream
    RCSOFT(rcl_publish(&pub_wheel, &msg_wheel, NULL));
  }

  // --- Sonar publish + ESTOP update @ 10Hz ---
  if ((now - t_sonar) >= SONAR_PERIOD_MS) {
    t_sonar = now;
    sonar_update();  // refreshes range + ESTOP latch (consumed by control loop)
    msg_range.data = sonar_get_range_cm();
    RCSOFT(rcl_publish(&pub_range, &msg_range, NULL));
  }
}
