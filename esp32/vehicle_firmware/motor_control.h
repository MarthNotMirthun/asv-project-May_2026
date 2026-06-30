// ============================================================
// Module:      motor_control.h
// Description: L298N dual H-bridge driver for the ASV catamaran.
//              LEDC PWM generation, 80% duty hard cap, software
//              stall-current estimation/trip, and cmd_vel -> duty
//              mixing. Safety-critical: this is the only path that
//              energizes the thrusters.
// Target:      ESP32 #1 (vehicle), micro-ROS, Arduino framework
// Pipeline:    /cmd_vel (Twist) -> THIS -> L298N ENA/ENB PWM
// Author:      fpga-verilog-engineer agent (firmware task)
// Date:        2026-06-29
// ============================================================
//
// CLAUDE.md hardware contract sources:
//  - ENA -> GPIO25 (LEDC ch0), ENB -> GPIO26 (LEDC ch1)
//  - Max duty 80%: L298N ~2V drop, 80% on 11.1V = ~9V effective;
//    full duty risks over-voltage on thrusters.
//  - PWM frequency 20kHz: inaudible, clean drive for L298N.
//  - Stall trip: estimated current > 1.5A/channel for >100ms ->
//    cut PWM to 0, resume at 50% duty after 500ms.
//  - LICHIFIT RF-370 stall = 5-8.6A destroys L298N (3A peak) ->
//    the duty cap is NOT sufficient on its own; stall trip is mandatory.
//
#ifndef MOTOR_CONTROL_H
#define MOTOR_CONTROL_H

#include <Arduino.h>

// ---- Pin map (CLAUDE.md: ENA->GPIO25, ENB->GPIO26) ----
// L298N direction pins (IN1..IN4) set forward/reverse per channel.
// Direction pins chosen on free GPIO; adjust to match wiring harness.
#define MOTOR_ENA_PIN      25   // Left channel PWM (LEDC ch0)
#define MOTOR_ENB_PIN      26   // Right channel PWM (LEDC ch1)
#define MOTOR_IN1_PIN      32   // Left  direction A
#define MOTOR_IN2_PIN      33   // Left  direction B
#define MOTOR_IN3_PIN      18   // Right direction A
#define MOTOR_IN4_PIN      19   // Right direction B

// ---- LEDC configuration ----
#define MOTOR_LEDC_FREQ_HZ     20000  // 20kHz (CLAUDE.md: inaudible, clean L298N drive)
#define MOTOR_LEDC_RES_BITS    10     // 10-bit resolution -> duty 0..1023
#define MOTOR_LEDC_MAX         1023   // (2^10 - 1)
#define MOTOR_LEDC_CH_LEFT     0      // LEDC channel 0 (ENA)
#define MOTOR_LEDC_CH_RIGHT    1      // LEDC channel 1 (ENB)

// ---- Duty cap (CLAUDE.md: 80% hard cap to protect thrusters) ----
// 0.80 * 1023 = 818.4 -> floor to 818.
#define MOTOR_DUTY_CAP   818

// ---- Stall protection (CLAUDE.md: >1.5A/channel for >100ms -> trip) ----
// Software estimation: I ~= duty_fraction * Vbus / R_motor_est.
// Bench-validate with INA219/shunt; firmware estimates in real time.
#define MOTOR_VBUS_V              9.0f   // Effective bus after L298N drop (~9V)
#define MOTOR_R_EST_OHM          3.0f    // Placeholder RF-370 winding+wiring estimate; CALIBRATE at bench
#define MOTOR_STALL_CURRENT_A    1.5f    // CLAUDE.md trip threshold per channel
#define MOTOR_STALL_TIME_MS      100     // CLAUDE.md: sustained >100ms before trip
#define MOTOR_STALL_RECOVER_MS   500     // CLAUDE.md: hold 0 for 500ms, then resume at 50%
#define MOTOR_STALL_RESUME_FRAC  0.50f   // CLAUDE.md: resume at 50% duty

// ---- cmd_vel mixing ----
// Differential drive: linear.x = forward, angular.z = turn.
// Inputs are clamped to [-1,1] then scaled to capped duty.
#define MOTOR_CMD_TIMEOUT_MS  500   // Watchdog: zero PWM if no cmd_vel for >500ms

struct MotorState {
  int   left_duty;        // current applied duty 0..MOTOR_DUTY_CAP
  int   right_duty;
  bool  left_forward;
  bool  right_forward;
  bool  stalled_left;     // currently in stall-trip cutoff
  bool  stalled_right;
  bool  estop;            // external ESTOP (sonar) latched
  uint32_t stall_left_start_ms;
  uint32_t stall_right_start_ms;
  uint32_t stall_left_recover_ms;
  uint32_t stall_right_recover_ms;
  uint32_t last_cmd_ms;   // last cmd_vel arrival time
};

static MotorState g_motor;

// ---- Setup ----
inline void motor_setup() {
  pinMode(MOTOR_IN1_PIN, OUTPUT);
  pinMode(MOTOR_IN2_PIN, OUTPUT);
  pinMode(MOTOR_IN3_PIN, OUTPUT);
  pinMode(MOTOR_IN4_PIN, OUTPUT);

  // Legacy LEDC API (broadly compatible across arduino-esp32 cores).
  ledcSetup(MOTOR_LEDC_CH_LEFT,  MOTOR_LEDC_FREQ_HZ, MOTOR_LEDC_RES_BITS);
  ledcSetup(MOTOR_LEDC_CH_RIGHT, MOTOR_LEDC_FREQ_HZ, MOTOR_LEDC_RES_BITS);
  ledcAttachPin(MOTOR_ENA_PIN, MOTOR_LEDC_CH_LEFT);
  ledcAttachPin(MOTOR_ENB_PIN, MOTOR_LEDC_CH_RIGHT);

  g_motor.left_duty = 0;
  g_motor.right_duty = 0;
  g_motor.left_forward = true;
  g_motor.right_forward = true;
  g_motor.stalled_left = false;
  g_motor.stalled_right = false;
  g_motor.estop = false;
  g_motor.stall_left_start_ms = 0;
  g_motor.stall_right_start_ms = 0;
  g_motor.stall_left_recover_ms = 0;
  g_motor.stall_right_recover_ms = 0;
  g_motor.last_cmd_ms = 0;

  // Force outputs low at boot.
  ledcWrite(MOTOR_LEDC_CH_LEFT, 0);
  ledcWrite(MOTOR_LEDC_CH_RIGHT, 0);
}

// Apply direction pins for a channel.
inline void motor_set_dir(bool forward, int in_a, int in_b) {
  digitalWrite(in_a, forward ? HIGH : LOW);
  digitalWrite(in_b, forward ? LOW  : HIGH);
}

// Estimate channel current from applied duty (CLAUDE.md software estimation).
inline float motor_estimate_current(int duty) {
  float frac = (float)duty / (float)MOTOR_LEDC_MAX;
  return frac * MOTOR_VBUS_V / MOTOR_R_EST_OHM;
}

// Clamp helper.
inline float motor_clampf(float v, float lo, float hi) {
  if (v < lo) return lo;
  if (v > hi) return hi;
  return v;
}

// Record a new cmd_vel command (called from the ROS subscriber callback).
// linear_x and angular_z expected roughly in [-1,1]; clamped here.
inline void motor_on_cmd_vel(float linear_x, float angular_z) {
  g_motor.last_cmd_ms = millis();

  float lx = motor_clampf(linear_x, -1.0f, 1.0f);
  float az = motor_clampf(angular_z, -1.0f, 1.0f);

  // Differential mix.
  float left  = lx - az;
  float right = lx + az;
  left  = motor_clampf(left,  -1.0f, 1.0f);
  right = motor_clampf(right, -1.0f, 1.0f);

  g_motor.left_forward  = (left  >= 0.0f);
  g_motor.right_forward = (right >= 0.0f);

  // Magnitude -> duty, capped at 80%.
  g_motor.left_duty  = (int)(fabsf(left)  * (float)MOTOR_DUTY_CAP);
  g_motor.right_duty = (int)(fabsf(right) * (float)MOTOR_DUTY_CAP);
}

// External ESTOP from sonar collision logic.
inline void motor_set_estop(bool estop) {
  g_motor.estop = estop;
}

// Stall state machine for one channel. Returns the duty to actually apply.
// Runs every control loop iteration (not just on cmd_vel) so it fires even
// if cmd_vel stops arriving — CLAUDE.md requirement.
inline int motor_stall_guard(int requested_duty,
                             bool *stalled,
                             uint32_t *stall_start_ms,
                             uint32_t *recover_ms) {
  uint32_t now = millis();

  // In recovery cutoff: hold 0 until recover window elapses, then resume @ 50%.
  if (*stalled) {
    if (now < *recover_ms) {
      return 0;
    }
    // Recovery window elapsed: resume at 50% of requested (CLAUDE.md).
    *stalled = false;
    *stall_start_ms = 0;
    return (int)((float)requested_duty * MOTOR_STALL_RESUME_FRAC);
  }

  // Not stalled: check estimated current against threshold.
  float i_est = motor_estimate_current(requested_duty);
  if (i_est > MOTOR_STALL_CURRENT_A) {
    if (*stall_start_ms == 0) {
      *stall_start_ms = now;  // start timing the over-current condition
    } else if ((now - *stall_start_ms) >= MOTOR_STALL_TIME_MS) {
      // Sustained over-current -> trip.
      *stalled = true;
      *recover_ms = now + MOTOR_STALL_RECOVER_MS;
      return 0;
    }
  } else {
    *stall_start_ms = 0;  // over-current cleared before trip
  }
  return requested_duty;
}

// Main motor update — call every control loop iteration.
// Order of overrides: ESTOP > cmd watchdog > stall guard > duty cap.
inline void motor_update() {
  int left_req  = g_motor.left_duty;
  int right_req = g_motor.right_duty;

  // ESTOP from sonar: zero immediately.
  if (g_motor.estop) {
    left_req = 0;
    right_req = 0;
  }

  // cmd_vel watchdog: if commands stale, zero PWM (safety stop).
  if ((millis() - g_motor.last_cmd_ms) > MOTOR_CMD_TIMEOUT_MS) {
    left_req = 0;
    right_req = 0;
  }

  // Stall guard runs every loop regardless of cmd_vel arrival.
  int left_out = motor_stall_guard(left_req,
                                   &g_motor.stalled_left,
                                   &g_motor.stall_left_start_ms,
                                   &g_motor.stall_left_recover_ms);
  int right_out = motor_stall_guard(right_req,
                                    &g_motor.stalled_right,
                                    &g_motor.stall_right_start_ms,
                                    &g_motor.stall_right_recover_ms);

  // Final 80% duty cap clamp (defense in depth).
  if (left_out  > MOTOR_DUTY_CAP) left_out  = MOTOR_DUTY_CAP;
  if (right_out > MOTOR_DUTY_CAP) right_out = MOTOR_DUTY_CAP;
  if (left_out  < 0) left_out  = 0;
  if (right_out < 0) right_out = 0;

  // Apply direction + PWM.
  motor_set_dir(g_motor.left_forward,  MOTOR_IN1_PIN, MOTOR_IN2_PIN);
  motor_set_dir(g_motor.right_forward, MOTOR_IN3_PIN, MOTOR_IN4_PIN);
  ledcWrite(MOTOR_LEDC_CH_LEFT,  left_out);
  ledcWrite(MOTOR_LEDC_CH_RIGHT, right_out);

  // Cache the actually-applied duty for wheel-velocity estimation.
  g_motor.left_duty  = left_out;
  g_motor.right_duty = right_out;
}

// Accessors for wheel-velocity estimation (main sketch).
inline int  motor_get_left_duty()  { return g_motor.left_duty; }
inline int  motor_get_right_duty() { return g_motor.right_duty; }
inline bool motor_get_left_fwd()   { return g_motor.left_forward; }
inline bool motor_get_right_fwd()  { return g_motor.right_forward; }

#endif // MOTOR_CONTROL_H
