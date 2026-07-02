#!/usr/bin/env python3
# ============================================================
# Module:      collision_safety_node.py
# Description: Hard ESTOP override. Gates /cmd_vel_raw against
#              /collision/range_cm before it reaches motor_driver_node.
#              Highest-priority node in the vehicle control chain.
# Target:      Raspberry Pi 4, ROS 2 Jazzy
# Pipeline:    acoustic_homing_node -> /cmd_vel_raw ---\
#              ESP32 vehicle_firmware -> /collision/range_cm -+-> THIS
#              -> /cmd_vel_safe -> motor_driver_node
# Date:        2026-07-01
# ============================================================
#
# REDUNDANCY NOTE: esp32/vehicle_firmware/sonar_driver.h already
# implements an independent, lower-latency ESTOP on-device (30cm
# trigger, 1s clear hysteresis at 10Hz), wired directly into
# motor_control.h's motor_update() so the firmware zeroes PWM even if
# the Pi/ROS graph is unhealthy. This node is a second, Pi-side layer:
# it stops the *commanded* velocity before it is even sent, which lets
# acoustic_homing_node observe that its command was overridden (via
# this node's WARNING log) and matters once mission-level behaviors
# (e.g. FC-8 egress) need to react to a near-obstacle condition rather
# than just trust the firmware's silent local cutoff.
#
# WIRING NOTE: subscribes /cmd_vel_raw (NOT /cmd_vel) -- see
# motor_driver_node.py's header for why /cmd_vel is reserved as the
# single final topic to the ESP32.
#
import rclpy
from rclpy.node import Node
from rclpy.qos import QoSProfile, ReliabilityPolicy, HistoryPolicy

from geometry_msgs.msg import Twist
from std_msgs.msg import Float32

ESTOP_THRESHOLD_CM = 30.0   # NOT 25cm -- JSN-SR04T blind zone is 25cm (CLAUDE.md)
RANGE_TIMEOUT_S = 1.0       # no /collision/range_cm in 1s -> ESTOP (sensor-failure-safe)
TIMEOUT_CHECK_PERIOD_S = 0.2


class CollisionSafetyNode(Node):
    def __init__(self):
        super().__init__('collision_safety_node')

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

        self.sub_range = self.create_subscription(
            Float32, '/collision/range_cm', self._on_range, sensor_qos)
        self.sub_cmd_vel = self.create_subscription(
            Twist, '/cmd_vel_raw', self._on_cmd_vel, reliable_qos)
        self.pub_cmd_vel_safe = self.create_publisher(Twist, '/cmd_vel_safe', reliable_qos)

        self._last_range_cm = None
        self._last_range_time = None
        self._estop_active = False

        self._timeout_timer = self.create_timer(TIMEOUT_CHECK_PERIOD_S, self._check_range_timeout)

        self.get_logger().info(
            f'collision_safety_node: ESTOP threshold={ESTOP_THRESHOLD_CM}cm, '
            f'sensor timeout={RANGE_TIMEOUT_S}s')

    def _on_range(self, msg: Float32):
        self._last_range_cm = msg.data
        self._last_range_time = self.get_clock().now()

    def _in_estop(self) -> bool:
        if self._last_range_cm is None:
            return True  # never received a reading -> fail safe
        return self._last_range_cm <= ESTOP_THRESHOLD_CM

    def _on_cmd_vel(self, msg: Twist):
        estop = self._in_estop()

        if estop and not self._estop_active:
            self.get_logger().warning(
                f'collision_safety_node: ESTOP engaged, range={self._last_range_cm}cm')
        elif not estop and self._estop_active:
            self.get_logger().info('collision_safety_node: ESTOP cleared')
        self._estop_active = estop

        if estop:
            self.pub_cmd_vel_safe.publish(Twist())
        else:
            self.pub_cmd_vel_safe.publish(msg)

    def _check_range_timeout(self):
        if self._last_range_time is None:
            return
        elapsed = (self.get_clock().now() - self._last_range_time).nanoseconds / 1e9
        if elapsed > RANGE_TIMEOUT_S and not self._estop_active:
            self._estop_active = True
            self._last_range_cm = None
            self.get_logger().warning(
                f'collision_safety_node: no /collision/range_cm for {elapsed:.2f}s, '
                'ESTOP engaged (sensor-failure-safe)', throttle_duration_sec=1.0)
            self.pub_cmd_vel_safe.publish(Twist())


def main(args=None):
    rclpy.init(args=args)
    node = CollisionSafetyNode()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == '__main__':
    main()
