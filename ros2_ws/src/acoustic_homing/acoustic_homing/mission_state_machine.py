#!/usr/bin/env python3
# ============================================================
# Module:      mission_state_machine.py
# Description: High-level mission monitor and logger. Observes
#              acoustic_homing_node's state/target/SNR topics and
#              produces a timestamped event log for post-demo
#              analysis. Does NOT control motors.
# Target:      Raspberry Pi 4, ROS 2 Jazzy
# Pipeline:    acoustic_homing_node -> /mission/state, /mission/target,
#              /acoustic/corr_snr -> THIS -> /mission/log, /mission/complete
# Date:        2026-07-01
# ============================================================
import time

import rclpy
from rclpy.node import Node
from rclpy.qos import QoSProfile, ReliabilityPolicy, HistoryPolicy

from std_msgs.msg import String, Bool, UInt8, Float32

ARRIVED_STATES = ('ARRIVED_1', 'ARRIVED_2')
COMPLETE_STATE = 'ARRIVED_2'


class MissionStateMachine(Node):
    def __init__(self):
        super().__init__('mission_state_machine')

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

        self.sub_state = self.create_subscription(
            String, '/mission/state', self._on_state, reliable_qos)
        self.sub_target = self.create_subscription(
            UInt8, '/mission/target', self._on_target, reliable_qos)
        self.sub_snr = self.create_subscription(
            Float32, '/acoustic/corr_snr', self._on_snr, sensor_qos)

        self.pub_log = self.create_publisher(String, '/mission/log', reliable_qos)
        self.pub_complete = self.create_publisher(Bool, '/mission/complete', reliable_qos)

        self._current_state = None
        self._state_entry_time = None
        self._current_target = 0
        self._latest_snr = None
        self._mission_complete = False
        self._arrived_logged = set()

        self.get_logger().info('mission_state_machine: monitoring, motors untouched')

    def _log(self, text: str):
        stamped = f'[{time.strftime("%Y-%m-%d %H:%M:%S")}] {text}'
        self.pub_log.publish(String(data=stamped))
        self.get_logger().info(stamped)

    def _on_target(self, msg: UInt8):
        self._current_target = msg.data

    def _on_snr(self, msg: Float32):
        self._latest_snr = msg.data

    def _on_state(self, msg: String):
        new_state = msg.data
        now = self.get_clock().now()

        if self._current_state is not None and self._current_state != new_state:
            elapsed = (now - self._state_entry_time).nanoseconds / 1e9
            self._log(f'STATE {self._current_state} -> {new_state} '
                      f'(spent {elapsed:.2f}s in {self._current_state}, '
                      f'target={self._current_target})')
        elif self._current_state is None:
            self._log(f'STATE INIT -> {new_state}')

        state_changed = new_state != self._current_state
        self._current_state = new_state
        if state_changed:
            self._state_entry_time = now

        if new_state in ARRIVED_STATES and new_state not in self._arrived_logged:
            self._arrived_logged.add(new_state)
            self._log(f'{new_state}: corr_snr={self._latest_snr}')

        if new_state == COMPLETE_STATE and not self._mission_complete:
            self._mission_complete = True
            self._log('MISSION COMPLETE')
        self.pub_complete.publish(Bool(data=self._mission_complete))


def main(args=None):
    rclpy.init(args=args)
    node = MissionStateMachine()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == '__main__':
    main()
