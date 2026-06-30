#!/usr/bin/env python3
# ============================================================
# Module:      fpga_uart_node.py
# Description: Reads the FPGA's 8-byte UART packet stream and
#              republishes it as ROS 2 topics. Bridges the Tang
#              Nano 20K matched-filter pipeline to acoustic_homing_node.
# Target:      Raspberry Pi 4, ROS 2 Jazzy
# Pipeline:    FPGA uart_tx -> /dev/ttyAMA0 @ 115200 -> THIS ->
#              /acoustic/corr_snr, /acoustic/peak_lag, /acoustic/target_id
# Date:        2026-06-30
# ============================================================
#
# CLAUDE.md / TRAJECTORY.md contract:
#  - 8-byte packet: [target_id][peak_lag_H][peak_lag_L]
#    [corr_peak_H][corr_peak_L][snr][checksum][0xFF]
#  - checksum = XOR of bytes 0-5; terminator = 0xFF (byte 7)
#  - FC-5/FC-6: snr is the primary SNR-gradient homing signal ->
#    published as /acoustic/corr_snr (Float32). peak_lag is a
#    diagnostic sample-index only, never meters/range. corr_peak
#    (bytes 3-4) is not republished as its own topic here; it is
#    the FPGA-internal magnitude that peak_detector.v already
#    reduced into the snr byte.
#  - Pi UART: /dev/ttyAMA0 @ 115200 baud (CLAUDE.md UART Streaming
#    Hardware Contract).
#
import rclpy
from rclpy.node import Node
from rclpy.qos import QoSProfile, ReliabilityPolicy, HistoryPolicy

from std_msgs.msg import Float32, UInt16, UInt8

import serial

PACKET_LEN = 8
TERMINATOR = 0xFF
SERIAL_PORT = '/dev/ttyAMA0'
SERIAL_BAUD = 115200
POLL_PERIOD_S = 0.005  # 5ms poll, well under the 50ms/20Hz packet period


class FpgaUartNode(Node):
    def __init__(self):
        super().__init__('fpga_uart_node')

        qos = QoSProfile(
            reliability=ReliabilityPolicy.BEST_EFFORT,
            history=HistoryPolicy.KEEP_LAST,
            depth=10,
        )
        self.pub_corr_snr = self.create_publisher(Float32, '/acoustic/corr_snr', qos)
        self.pub_peak_lag = self.create_publisher(UInt16, '/acoustic/peak_lag', qos)
        self.pub_target_id = self.create_publisher(UInt8, '/acoustic/target_id', qos)

        self._buf = bytearray()

        try:
            self._ser = serial.Serial(SERIAL_PORT, SERIAL_BAUD, timeout=0)
        except serial.SerialException as e:
            self.get_logger().error(f'fpga_uart_node: failed to open {SERIAL_PORT}: {e}')
            raise

        self._timer = self.create_timer(POLL_PERIOD_S, self._poll_serial)
        self.get_logger().info(f'fpga_uart_node: listening on {SERIAL_PORT} @ {SERIAL_BAUD} baud')

    def _poll_serial(self):
        try:
            n = self._ser.in_waiting
        except Exception as e:
            self.get_logger().error(f'fpga_uart_node: serial read error: {e}', throttle_duration_sec=1.0)
            return
        if n <= 0:
            return
        self._buf.extend(self._ser.read(n))
        self._process_buffer()

    def _process_buffer(self):
        # Synchronize on the 0xFF terminator at offset 7. If the buffer
        # doesn't align (e.g. partial packet at startup, or a dropped/
        # corrupted byte), slide one byte at a time until it does. This
        # bounds resync time to at most PACKET_LEN-1 extra bytes.
        while len(self._buf) >= PACKET_LEN:
            frame = self._buf[:PACKET_LEN]

            if frame[7] != TERMINATOR:
                self.get_logger().warning(
                    'fpga_uart_node: 0xFF terminator not found at expected position, resyncing',
                    throttle_duration_sec=1.0)
                del self._buf[0:1]
                continue

            checksum = 0
            for b in frame[0:6]:
                checksum ^= b
            if checksum != frame[6]:
                self.get_logger().warning(
                    'fpga_uart_node: checksum mismatch, dropping byte to resync',
                    throttle_duration_sec=1.0)
                del self._buf[0:1]
                continue

            self._publish_frame(frame)
            del self._buf[0:PACKET_LEN]

    def _publish_frame(self, frame: bytearray):
        target_id = frame[0]
        peak_lag = (frame[1] << 8) | frame[2]
        snr = frame[5]

        self.pub_corr_snr.publish(Float32(data=float(snr)))
        self.pub_peak_lag.publish(UInt16(data=peak_lag))
        self.pub_target_id.publish(UInt8(data=target_id))

    def destroy_node(self):
        if hasattr(self, '_ser') and self._ser.is_open:
            self._ser.close()
        super().destroy_node()


def main(args=None):
    rclpy.init(args=args)
    node = FpgaUartNode()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == '__main__':
    main()
