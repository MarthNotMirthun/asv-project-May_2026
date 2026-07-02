#!/usr/bin/env python3
# ============================================================
# Module:      dead_reckoning_node.py
# Description: Fuses IMU yaw rate + wheel-derived forward speed
#              into a 2D EKF dead-reckoning odometry estimate,
#              used by acoustic_homing_node to smooth heading
#              between acoustic pings (FC-6).
# Target:      Raspberry Pi 4, ROS 2 Jazzy
# Pipeline:    ESP32 vehicle_firmware -> /imu/data (100Hz),
#              /wheel/velocity (50Hz, TwistStamped) -> THIS ->
#              /odometry/filtered (50Hz)
# Date:        2026-07-01
# ============================================================
#
# CUTTABLE FOR MVP: acoustic_homing_node's SNR-gradient homing does
# NOT require this node. It can run on raw /imu/data (yaw rate only,
# no position estimate) with reduced heading-hold accuracy between
# pings. If schedule pressure forces a cut, skip this node first --
# see CLAUDE.md Week 6 priorities and TRAJECTORY.md Section 4 "what to
# cut if the schedule slips further".
#
# IMPLEMENTATION NOTE: this is a from-scratch, predict-only EKF (a
# unicycle kinematic model with covariance propagation), NOT a wrapper
# around the `robot_localization` ROS package. Reasons:
#  1. There is no absolute position/orientation measurement anywhere
#     in this system (GPS-denied, FC-5) -- /acoustic/corr_snr is a
#     gradient signal, not a pose fix -- so there is no correction
#     step to perform between pings. A full 15-state
#     robot_localization EKF is built to fuse *correcting* measurement
#     sources; without one, it reduces to exactly this predict-only
#     model, at a much higher CPU/RAM cost than a Pi 4 1GB should
#     spend on it.
#  2. config/ekf_params.yaml is still shipped as a documented
#     robot_localization-compatible reference, in case a V2 upgrade
#     (e.g. TDOA fix, or a future absolute sensor) adds a real
#     correction source and the team wants to swap to the full
#     package without redesigning the topic contract.
#
# WIRE FORMAT NOTE: /wheel/velocity is geometry_msgs/TwistStamped
# (NOT Float32MultiArray as an earlier draft spec assumed) --
# esp32/vehicle_firmware/vehicle_firmware.ino (already built, Jun 29)
# publishes twist.linear.x = mean forward speed and
# twist.angular.z = (right_vel - left_vel) RAW, explicitly "scaled by
# track width downstream" per that file's own comment. This node
# divides by wheel_base to recover an actual rad/s estimate.
#
import math

import rclpy
from rclpy.node import Node
from rclpy.qos import QoSProfile, ReliabilityPolicy, HistoryPolicy

from geometry_msgs.msg import TwistStamped
from sensor_msgs.msg import Imu
from nav_msgs.msg import Odometry

PREDICT_RATE_HZ = 50.0
IMU_STALE_S = 0.2  # if IMU hasn't updated in this long, fall back to wheel-derived omega


class DeadReckoningNode(Node):
    def __init__(self):
        super().__init__('dead_reckoning_node')

        self.declare_parameter('wheel_base', 0.4)
        self.declare_parameter('process_noise_xy', 0.02)      # m^2 per predict step
        self.declare_parameter('process_noise_theta', 0.01)   # rad^2 per predict step
        self.wheel_base = self.get_parameter('wheel_base').value
        self.q_xy = self.get_parameter('process_noise_xy').value
        self.q_theta = self.get_parameter('process_noise_theta').value

        sensor_qos = QoSProfile(
            reliability=ReliabilityPolicy.BEST_EFFORT,
            history=HistoryPolicy.KEEP_LAST,
            depth=10,
        )

        self.sub_imu = self.create_subscription(Imu, '/imu/data', self._on_imu, sensor_qos)
        self.sub_wheel = self.create_subscription(
            TwistStamped, '/wheel/velocity', self._on_wheel, sensor_qos)
        self.pub_odom = self.create_publisher(Odometry, '/odometry/filtered', sensor_qos)

        # EKF state [x, y, theta], reset to zero at startup (no absolute reference exists).
        self.x = 0.0
        self.y = 0.0
        self.theta = 0.0
        self.P = [[0.0, 0.0, 0.0],
                  [0.0, 0.0, 0.0],
                  [0.0, 0.0, 0.0]]

        self._v = 0.0            # latest wheel-derived forward speed (m/s)
        self._omega_wheel = 0.0  # latest wheel-derived yaw rate (rad/s), fallback only
        self._omega_imu = 0.0    # latest IMU gyro yaw rate (rad/s)
        self._last_imu_time = None

        self._predict_timer = self.create_timer(1.0 / PREDICT_RATE_HZ, self._predict_step)

        self.get_logger().info(
            f'dead_reckoning_node: wheel_base={self.wheel_base}m, predict @ {PREDICT_RATE_HZ}Hz. '
            'Predict-only EKF (no correction source in V1) -- see module docstring.')

    def _on_imu(self, msg: Imu):
        self._omega_imu = msg.angular_velocity.z
        self._last_imu_time = self.get_clock().now()

    def _on_wheel(self, msg: TwistStamped):
        self._v = msg.twist.linear.x
        if self.wheel_base != 0.0:
            self._omega_wheel = msg.twist.angular.z / self.wheel_base
        else:
            self._omega_wheel = 0.0

    def _current_omega(self) -> float:
        if self._last_imu_time is not None:
            age = (self.get_clock().now() - self._last_imu_time).nanoseconds / 1e9
            if age <= IMU_STALE_S:
                return self._omega_imu
        return self._omega_wheel  # IMU stale or never received -> fall back

    def _predict_step(self):
        dt = 1.0 / PREDICT_RATE_HZ
        v = self._v
        omega = self._current_omega()

        # Unicycle kinematic prediction.
        self.theta += omega * dt
        self.theta = math.atan2(math.sin(self.theta), math.cos(self.theta))  # wrap to [-pi, pi]
        self.x += v * math.cos(self.theta) * dt
        self.y += v * math.sin(self.theta) * dt

        # Covariance propagation (Jacobian of the unicycle model wrt state).
        s, c = math.sin(self.theta), math.cos(self.theta)
        F = [[1.0, 0.0, -v * s * dt],
             [0.0, 1.0, v * c * dt],
             [0.0, 0.0, 1.0]]
        Q = [[self.q_xy, 0.0, 0.0],
             [0.0, self.q_xy, 0.0],
             [0.0, 0.0, self.q_theta]]
        self.P = self._propagate_covariance(F, self.P, Q)

        self._publish_odometry(v, omega)

    @staticmethod
    def _propagate_covariance(F, P, Q):
        # P_new = F P F^T + Q, all 3x3.
        FP = [[sum(F[i][k] * P[k][j] for k in range(3)) for j in range(3)] for i in range(3)]
        FPFt = [[sum(FP[i][k] * F[j][k] for k in range(3)) for j in range(3)] for i in range(3)]
        return [[FPFt[i][j] + Q[i][j] for j in range(3)] for i in range(3)]

    def _publish_odometry(self, v: float, omega: float):
        msg = Odometry()
        msg.header.stamp = self.get_clock().now().to_msg()
        msg.header.frame_id = 'odom'
        msg.child_frame_id = 'base_link'

        msg.pose.pose.position.x = self.x
        msg.pose.pose.position.y = self.y
        msg.pose.pose.position.z = 0.0
        qz = math.sin(self.theta / 2.0)
        qw = math.cos(self.theta / 2.0)
        msg.pose.pose.orientation.x = 0.0
        msg.pose.pose.orientation.y = 0.0
        msg.pose.pose.orientation.z = qz
        msg.pose.pose.orientation.w = qw

        cov = [0.0] * 36
        cov[0] = self.P[0][0]   # x-x
        cov[1] = self.P[0][1]   # x-y
        cov[5] = self.P[0][2]   # x-yaw
        cov[6] = self.P[1][0]   # y-x
        cov[7] = self.P[1][1]   # y-y
        cov[11] = self.P[1][2]  # y-yaw
        cov[30] = self.P[2][0]  # yaw-x
        cov[31] = self.P[2][1]  # yaw-y
        cov[35] = self.P[2][2]  # yaw-yaw
        msg.pose.covariance = cov

        msg.twist.twist.linear.x = v
        msg.twist.twist.angular.z = omega

        self.pub_odom.publish(msg)


def main(args=None):
    rclpy.init(args=args)
    node = DeadReckoningNode()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == '__main__':
    main()
