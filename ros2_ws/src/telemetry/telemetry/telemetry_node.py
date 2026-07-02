#!/usr/bin/env python3
# ============================================================
# Module:      telemetry_node.py
# Description: Sends mission state + acoustic SNR to the Arduino
#              Uno R4 WiFi shore display over UDP. Non-critical --
#              the mission continues even if the shore display is
#              unreachable.
# Target:      Raspberry Pi 4, ROS 2 Jazzy
# Pipeline:    acoustic_homing_node -> /mission/state, /mission/target;
#              fpga_uart_node -> /acoustic/corr_snr -> THIS -> UDP ->
#              Arduino Uno R4 WiFi shore display
# Date:        2026-07-01
# ============================================================
import json
import socket

import rclpy
from rclpy.node import Node
from rclpy.qos import QoSProfile, ReliabilityPolicy, HistoryPolicy

from std_msgs.msg import String, Float32, UInt8

SEND_PERIOD_S = 0.5  # 500ms


class TelemetryNode(Node):
    def __init__(self):
        super().__init__('telemetry_node')

        self.declare_parameter('shore_display_ip', '192.168.1.255')
        self.declare_parameter('shore_display_port', 8888)
        self.shore_ip = self.get_parameter('shore_display_ip').value
        self.shore_port = self.get_parameter('shore_display_port').value

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

        self._state = 'INIT'
        self._target = 0
        self._snr = 0.0

        self._sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self._sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
        self._wifi_warned = False

        self._send_timer = self.create_timer(SEND_PERIOD_S, self._send_packet)

        self.get_logger().info(
            f'telemetry_node: sending to {self.shore_ip}:{self.shore_port} every {SEND_PERIOD_S}s')

    def _on_state(self, msg: String):
        self._state = msg.data

    def _on_target(self, msg: UInt8):
        self._target = msg.data

    def _on_snr(self, msg: Float32):
        self._snr = msg.data

    def _send_packet(self):
        payload = json.dumps({
            'state': self._state,
            'snr': self._snr,
            'target': self._target,
        }).encode('utf-8')
        try:
            self._sock.sendto(payload, (self.shore_ip, self.shore_port))
            self._wifi_warned = False
        except OSError as e:
            # Telemetry is non-critical (CLAUDE.md): log once, keep the mission going.
            if not self._wifi_warned:
                self.get_logger().warning(
                    f'telemetry_node: UDP send failed ({e}), continuing mission without telemetry')
                self._wifi_warned = True

    def destroy_node(self):
        self._sock.close()
        super().destroy_node()


def main(args=None):
    rclpy.init(args=args)
    node = TelemetryNode()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == '__main__':
    main()
