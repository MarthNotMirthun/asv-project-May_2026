#!/usr/bin/env python3
# ============================================================
# Module:      motor_driver_node.py
# Description: Final Pi-side gate before the ESP32 vehicle
#              firmware. Converts the safety-gated Twist into
#              differential thrust for diagnostics, enforces an
#              80% duty ceiling (DL-1) as a second layer above the
#              ESP32's own cap, runs a 500ms cmd watchdog, and
#              republishes the single Twist the ESP32 subscribes to.
# Target:      Raspberry Pi 4, ROS 2 Jazzy
# Pipeline:    acoustic_homing_node -> /cmd_vel_raw -> collision_safety_node
#              -> /cmd_vel_safe -> THIS -> /cmd_vel -> micro-ROS agent ->
#              ESP32 vehicle_firmware.ino (already subscribes /cmd_vel)
# Date:        2026-07-01
# ============================================================
#
# WIRING NOTE (deviation from the literal node spec, deliberate):
#  The original per-node spec has motor_driver_node subscribe directly
#  to /cmd_vel -- the SAME topic acoustic_homing_node publishes to, and
#  ALSO the same topic collision_safety_node reads from. That wiring
#  bypasses collision_safety_node entirely (it would publish
#  /cmd_vel_safe to nobody, since nothing subscribed to it). Since
#  esp32/vehicle_firmware/vehicle_firmware.ino (already built, Jun 29)
#  hard-subscribes to the literal topic name "/cmd_vel", that name is
#  reserved as the SINGLE final topic with exactly one publisher: this
#  node. acoustic_homing_node's raw output is therefore renamed
#  /cmd_vel_raw upstream of collision_safety_node so the safety gate is
#  actually in the loop. See collision_safety_node.py and
#  acoustic_homing_node.py for the matching halves of this fix.
#
# NOTE ON REDUNDANCY: esp32/vehicle_firmware/motor_control.h already
# does its own linear/angular -> left/right mix, its own 80% duty cap,
# and its own 500ms cmd_vel watchdog on-device. This node's mixing and
# clamping is therefore defense-in-depth (protects against a Pi-side
# bug publishing something the firmware's own clamp would still catch)
# plus the /motor/status diagnostic the firmware has no channel to
# report over. It intentionally duplicates none of the firmware's
# stall-current or ESTOP logic -- that stays on-device only.
#
import rclpy
from rclpy.node import Node
from rclpy.qos import QoSProfile, ReliabilityPolicy, HistoryPolicy

from geometry_msgs.msg import Twist
from std_msgs.msg import String

CMD_WATCHDOG_PERIOD_S = 0.5    # 500ms: no /cmd_vel_safe -> zero velocity
WATCHDOG_CHECK_PERIOD_S = 0.1  # check cadence, well under the 500ms window
MAX_DUTY_FRAC = 0.8            # DL-1: 80% duty ceiling


class MotorDriverNode(Node):
    def __init__(self):
        super().__init__('motor_driver_node')

        self.declare_parameter('wheel_base', 0.4)  # 40cm beam (CLAUDE.md)
        self.wheel_base = self.get_parameter('wheel_base').value

        reliable_qos = QoSProfile(
            reliability=ReliabilityPolicy.RELIABLE,
            history=HistoryPolicy.KEEP_LAST,
            depth=10,
        )

        self.sub_cmd_vel_safe = self.create_subscription(
            Twist, '/cmd_vel_safe', self._on_cmd_vel_safe, reliable_qos)
        self.pub_cmd_vel = self.create_publisher(Twist, '/cmd_vel', reliable_qos)
        self.pub_status = self.create_publisher(String, '/motor/status', reliable_qos)

        self._last_cmd_time = None
        self._watchdog_timer = self.create_timer(WATCHDOG_CHECK_PERIOD_S, self._check_watchdog)

        self.get_logger().info(
            f'motor_driver_node: wheel_base={self.wheel_base}m, '
            f'duty ceiling={MAX_DUTY_FRAC*100:.0f}%, watchdog={CMD_WATCHDOG_PERIOD_S}s')

    def _mix_and_clamp(self, linear_x: float, angular_z: float):
        left = linear_x - angular_z * self.wheel_base / 2.0
        right = linear_x + angular_z * self.wheel_base / 2.0

        left = max(-1.0, min(1.0, left))
        right = max(-1.0, min(1.0, right))

        # If either wheel exceeds the duty ceiling, scale both down together
        # so the commanded turn/heading ratio is preserved.
        peak = max(abs(left), abs(right))
        if peak > MAX_DUTY_FRAC and peak > 0.0:
            scale = MAX_DUTY_FRAC / peak
            left *= scale
            right *= scale

        return left, right

    def _on_cmd_vel_safe(self, msg: Twist):
        self._last_cmd_time = self.get_clock().now()

        left, right = self._mix_and_clamp(msg.linear.x, msg.angular.z)

        # Republish the clamped command as the single /cmd_vel the ESP32
        # firmware subscribes to. The firmware re-derives its own
        # left/right mix from linear.x/angular.z, so we back-solve the
        # equivalent (already-clamped) Twist rather than sending raw duty.
        out = Twist()
        out.linear.x = (left + right) / 2.0
        out.angular.z = (right - left) / self.wheel_base if self.wheel_base != 0 else 0.0
        self.pub_cmd_vel.publish(out)

        status = String()
        status.data = f'left={left:+.2f} right={right:+.2f} src=cmd_vel_safe'
        self.pub_status.publish(status)

    def _check_watchdog(self):
        if self._last_cmd_time is None:
            return
        elapsed = (self.get_clock().now() - self._last_cmd_time).nanoseconds / 1e9
        if elapsed > CMD_WATCHDOG_PERIOD_S:
            self.pub_cmd_vel.publish(Twist())  # zero velocity, safety stop
            status = String()
            status.data = f'WATCHDOG: no /cmd_vel_safe for {elapsed:.2f}s, zeroing'
            self.pub_status.publish(status)
            self.get_logger().warning(
                f'motor_driver_node: watchdog tripped, {elapsed:.2f}s since last command',
                throttle_duration_sec=1.0)
            self._last_cmd_time = None  # avoid re-spamming until a new command arrives


def main(args=None):
    rclpy.init(args=args)
    node = MotorDriverNode()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == '__main__':
    main()
