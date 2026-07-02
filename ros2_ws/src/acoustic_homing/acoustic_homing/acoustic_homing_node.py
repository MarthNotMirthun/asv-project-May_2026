#!/usr/bin/env python3
# ============================================================
# Module:      acoustic_homing_node.py
# Description: The mission brain. SNR-gradient homing (FC-6) with
#              code-division dual-channel gating (FC-7) and a
#              mandatory egress maneuver between targets (FC-8).
# Target:      Raspberry Pi 4, ROS 2 Jazzy
# Pipeline:    fpga_uart_node -> /acoustic/corr_snr, /acoustic/target_id,
#              /acoustic/peak_lag; dead_reckoning_node -> /odometry/filtered
#              -> THIS -> /cmd_vel_raw -> collision_safety_node
# Date:        2026-07-01
# ============================================================
#
# WIRING NOTE: publishes /cmd_vel_raw, NOT /cmd_vel. The literal
# per-node spec has this node publish directly to /cmd_vel, the same
# topic esp32/vehicle_firmware/vehicle_firmware.ino (already built)
# hard-subscribes to. Publishing there directly would race with
# motor_driver_node's own /cmd_vel publish and bypass
# collision_safety_node's ESTOP gate entirely. See
# motor_driver_node.py's header for the full chain:
#   THIS -> /cmd_vel_raw -> collision_safety_node -> /cmd_vel_safe
#        -> motor_driver_node -> /cmd_vel -> ESP32
#
# FC-7 NOTE ON DUAL-CHANNEL GATING: the literal spec for HOMING_1's
# ARRIVED transition also asks this node to check that "target_id=2
# corr_snr is LOW". That check is NOT re-implemented here because it
# is already enforced upstream, on the FPGA, by peak_detector.v's
# relative K_SHIFT/FLOOR gate (FC-7): target_id is reported as 0x01
# ONLY when channel 1's magnitude beats channel 2's by the K_SHIFT
# ratio AND clears FLOOR; otherwise target_id is 0x00. The 8-byte
# packet carries one target_id/snr pair, not both channels' raw
# magnitudes, so there is nothing for the Pi side to independently
# re-check -- observing target_id==1 IS the dual-channel gate having
# already passed. Duplicating it here would require data the wire
# format doesn't carry.
#
import math
from enum import Enum, auto

import rclpy
from rclpy.node import Node
from rclpy.qos import QoSProfile, ReliabilityPolicy, HistoryPolicy

from geometry_msgs.msg import Twist
from std_msgs.msg import Float32, UInt8, UInt16, String
from nav_msgs.msg import Odometry

CONTROL_PERIOD_S = 0.05  # 20Hz, matches the FPGA packet rate


class State(Enum):
    INIT = auto()
    SCAN_1 = auto()
    ACQUIRING_1 = auto()
    HOMING_1 = auto()
    ARRIVED_1 = auto()
    EGRESS_1 = auto()
    SCAN_2 = auto()
    ACQUIRING_2 = auto()
    HOMING_2 = auto()
    ARRIVED_2 = auto()


class AcousticHomingNode(Node):
    def __init__(self):
        super().__init__('acoustic_homing_node')

        self.declare_parameter('snr_acquire_threshold', 50.0)
        self.declare_parameter('snr_arrived_threshold', 200.0)
        self.declare_parameter('scan_angular_velocity', 0.3)
        self.declare_parameter('homing_linear_velocity', 0.3)
        self.declare_parameter('egress_distance', 2.5)
        self.declare_parameter('dual_channel_low_threshold', 30.0)  # kept as a declared
        # param per spec; not evaluated directly -- see FC-7 note above.
        self.declare_parameter('arrived_pause_s', 2.0)
        self.declare_parameter('acquiring_confirm_readings', 5)
        self.declare_parameter('consecutive_required', 3)

        self.SNR_ACQUIRE = self.get_parameter('snr_acquire_threshold').value
        self.SNR_ARRIVED = self.get_parameter('snr_arrived_threshold').value
        self.SCAN_ANGULAR_VELOCITY = self.get_parameter('scan_angular_velocity').value
        self.HOMING_LINEAR_VELOCITY = self.get_parameter('homing_linear_velocity').value
        self.EGRESS_DISTANCE = self.get_parameter('egress_distance').value
        self.ARRIVED_PAUSE_S = self.get_parameter('arrived_pause_s').value
        self.ACQUIRING_CONFIRM_READINGS = self.get_parameter('acquiring_confirm_readings').value
        self.CONSECUTIVE_REQUIRED = self.get_parameter('consecutive_required').value

        sensor_qos = QoSProfile(
            reliability=ReliabilityPolicy.BEST_EFFORT,
            history=HistoryPolicy.KEEP_LAST,
            depth=10,
        )
        reliable_qos = QoSProfile(
            reliability=ReliabilityPolicy.RELIABLE,
            history=HistoryPolicy.KEEP_LAST,
            depth=10,
        )

        self.sub_snr = self.create_subscription(
            Float32, '/acoustic/corr_snr', self._on_snr, sensor_qos)
        self.sub_target = self.create_subscription(
            UInt8, '/acoustic/target_id', self._on_target_id, sensor_qos)
        self.sub_peak_lag = self.create_subscription(
            UInt16, '/acoustic/peak_lag', self._on_peak_lag, sensor_qos)
        self.sub_odom = self.create_subscription(
            Odometry, '/odometry/filtered', self._on_odom, sensor_qos)

        self.pub_cmd_vel = self.create_publisher(Twist, '/cmd_vel_raw', reliable_qos)
        self.pub_state = self.create_publisher(String, '/mission/state', reliable_qos)
        self.pub_target = self.create_publisher(UInt8, '/mission/target', reliable_qos)

        # Latest sensor values.
        self._snr = None
        self._target_id = 0
        self._peak_lag = 0
        self._odom = None
        self._have_acoustic_data = False

        # State machine.
        self.state = State.INIT
        self._consec_count = 0
        self._prev_snr_for_gradient = None
        self._turn_dir = 1.0
        self._arrived_time = None
        self._egress_start_xy = None

        self._timer = self.create_timer(CONTROL_PERIOD_S, self._control_step)

        self.get_logger().info(
            f'acoustic_homing_node: SNR_ACQUIRE={self.SNR_ACQUIRE}, '
            f'SNR_ARRIVED={self.SNR_ARRIVED}, EGRESS_DISTANCE={self.EGRESS_DISTANCE}m')

    # ---- Subscriptions ----
    def _on_snr(self, msg: Float32):
        self._snr = msg.data
        self._have_acoustic_data = True

    def _on_target_id(self, msg: UInt8):
        self._target_id = msg.data

    def _on_peak_lag(self, msg: UInt16):
        self._peak_lag = msg.data  # diagnostic only, per FC-5 -- never used for control

    def _on_odom(self, msg: Odometry):
        self._odom = msg

    # ---- State machine ----
    def _set_state(self, new_state: State):
        if new_state != self.state:
            self.get_logger().info(f'acoustic_homing_node: {self.state.name} -> {new_state.name}')
            self.state = new_state
            self._consec_count = 0
            self._prev_snr_for_gradient = None

    def _target_locked(self, target_id: int) -> bool:
        return self._target_id == target_id and self._snr is not None and self._snr > self.SNR_ACQUIRE

    def _target_arrived(self, target_id: int) -> bool:
        return self._target_id == target_id and self._snr is not None and self._snr > self.SNR_ARRIVED

    def _gradient_ascent_cmd(self) -> Twist:
        cmd = Twist()
        if self._snr is None:
            return cmd
        if self._prev_snr_for_gradient is None or self._snr >= self._prev_snr_for_gradient:
            cmd.linear.x = self.HOMING_LINEAR_VELOCITY
            cmd.angular.z = 0.0
        else:
            # SNR falling: hunt for a better heading. Alternate turn direction
            # each time it degrades so the search doesn't run away in one
            # direction on a noisy reading.
            self._turn_dir *= -1.0
            cmd.linear.x = self.HOMING_LINEAR_VELOCITY * 0.5
            cmd.angular.z = self._turn_dir * self.SCAN_ANGULAR_VELOCITY * 0.5
        self._prev_snr_for_gradient = self._snr
        return cmd

    def _egress_distance_traveled(self) -> float:
        if self._egress_start_xy is None or self._odom is None:
            return 0.0
        dx = self._odom.pose.pose.position.x - self._egress_start_xy[0]
        dy = self._odom.pose.pose.position.y - self._egress_start_xy[1]
        return math.hypot(dx, dy)

    def _control_step(self):
        cmd = Twist()

        if self.state == State.INIT:
            if self._have_acoustic_data:
                self._set_state(State.SCAN_1)

        elif self.state == State.SCAN_1:
            cmd.angular.z = self.SCAN_ANGULAR_VELOCITY
            if self._target_locked(1):
                self._consec_count += 1
                if self._consec_count >= self.CONSECUTIVE_REQUIRED:
                    self._set_state(State.ACQUIRING_1)
            else:
                self._consec_count = 0

        elif self.state == State.ACQUIRING_1:
            # Motors stopped while confirming signal stability.
            if self._target_locked(1):
                self._consec_count += 1
                if self._consec_count >= self.ACQUIRING_CONFIRM_READINGS:
                    self._set_state(State.HOMING_1)
            else:
                self._set_state(State.SCAN_1)  # lost lock -- resume scanning

        elif self.state == State.HOMING_1:
            if self._target_arrived(1):
                self._consec_count += 1
                if self._consec_count >= self.CONSECUTIVE_REQUIRED:
                    self._set_state(State.ARRIVED_1)
            else:
                self._consec_count = 0
                cmd = self._gradient_ascent_cmd()

        elif self.state == State.ARRIVED_1:
            if self._arrived_time is None:
                self._arrived_time = self.get_clock().now()
                self.get_logger().info(f'ARRIVED_1: corr_snr={self._snr}')
            elapsed = (self.get_clock().now() - self._arrived_time).nanoseconds / 1e9
            if elapsed >= self.ARRIVED_PAUSE_S:
                self._arrived_time = None
                self._egress_start_xy = (
                    (self._odom.pose.pose.position.x, self._odom.pose.pose.position.y)
                    if self._odom is not None else (0.0, 0.0))
                self._set_state(State.EGRESS_1)

        elif self.state == State.EGRESS_1:
            cmd.linear.x = -self.HOMING_LINEAR_VELOCITY
            if self._egress_distance_traveled() >= self.EGRESS_DISTANCE:
                self._set_state(State.SCAN_2)

        elif self.state == State.SCAN_2:
            cmd.angular.z = self.SCAN_ANGULAR_VELOCITY
            if self._target_locked(2):
                self._consec_count += 1
                if self._consec_count >= self.CONSECUTIVE_REQUIRED:
                    self._set_state(State.ACQUIRING_2)
            else:
                self._consec_count = 0

        elif self.state == State.ACQUIRING_2:
            if self._target_locked(2):
                self._consec_count += 1
                if self._consec_count >= self.ACQUIRING_CONFIRM_READINGS:
                    self._set_state(State.HOMING_2)
            else:
                self._set_state(State.SCAN_2)

        elif self.state == State.HOMING_2:
            if self._target_arrived(2):
                self._consec_count += 1
                if self._consec_count >= self.CONSECUTIVE_REQUIRED:
                    self._set_state(State.ARRIVED_2)
            else:
                self._consec_count = 0
                cmd = self._gradient_ascent_cmd()

        elif self.state == State.ARRIVED_2:
            if self._arrived_time is None:
                self._arrived_time = self.get_clock().now()
                self.get_logger().info(f'ARRIVED_2: corr_snr={self._snr} -- MISSION COMPLETE')
            # Terminal state: motors stay at zero, mission_state_machine
            # observes this via /mission/state and latches /mission/complete.

        self.pub_cmd_vel.publish(cmd)
        self.pub_state.publish(String(data=self.state.name))
        active_target = 1 if self.state.name.endswith('_1') else (
            2 if self.state.name.endswith('_2') else 0)
        self.pub_target.publish(UInt8(data=active_target))


def main(args=None):
    rclpy.init(args=args)
    node = AcousticHomingNode()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == '__main__':
    main()
