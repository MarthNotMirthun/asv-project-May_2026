---
name: project-milestones
description: Completed FPGA/Pi milestones and their dates, plus pending critical tasks — tracks what is actually done vs what CLAUDE.md planned
metadata:
  type: project
---

As of 2026-06-10 (Project Day 17, Week 3 Day 3):

**Completed:**
- FPGA: Gowin EDA installed, basic combinational + clocked logic confirmed
- FPGA: uart_tx.v written and synthesized onto Tang Nano (2026-06-08)
- FPGA: adc_interface.v — MSB-flip, OTR port, ENCODE output, 7-cycle pipeline latency (2026-06-09, validated 2026-06-10)
- FPGA: cic_decimator.v — R=8, shift=5, saturation clamp, sim PASS (2026-06-09, validated 2026-06-10)
- FPGA: fir_filter_bank1.v + fir_filter_bank2.v — 32-tap Hamming windowed-sinc, Q1.15, sim PASS (2026-06-10)
- Full pipeline validation: hw-validator, dsp-signal-validator, systems-integrator, verilog-sim-runner — ALL PASS (2026-06-10)
- Pi: Ubuntu 24.04.4 LTS + ROS 2 Jazzy installed and verified
- Pi: /dev/ttyAMA0 UART serial console disabled — port free for FPGA comms (2026-06-08)
- Pi: SSH, colcon, rosdep, heatsinks, avahi-daemon all working
- Parts: AD9226 ordered AliExpress ~2026-05-31, expected 2026-06-14 to 2026-06-21
- Parts: LiPo x2, charger, fuses, MPU-6050, TCT40 transducer pack, ESP32 x2 — all arrived
- Pin assignments confirmed: clk=pin4, tx=pin69, rst_n=pin88

**Critical carryover (not yet done as of Week 3 Day 3):**
- fpga/constraints/pipeline.cst — .cst timing constraints file NOT written
  Has been the #1 task for four consecutive sessions (W2 + W3D1 + W3D2 + W3D3).
  If not completed by Jun 14 (Week 3 end), technical status flips RED.
- Matched filter correlators x2 — not started (gates TOF calculator and pipeline integration)
- Peak detector + TOF calculator — not started
- Full pipeline integration — not started
- All 5 Amazon orders still pending: thrusters x2, L298N, MAX9814, JSN-SR04T, IP65 enclosure
- Home Depot PVC materials run not yet scheduled

**Why this matters:** All simulation modules are validated. The only FPGA gate remaining
is the .cst constraints file, which unlocks synthesis and all downstream build work.
The matched filter is the hardest and most time-sensitive FPGA component — it must
start no later than Week 3 Day 4 to preserve the Week 5 dual matched filter milestone.

**How to apply:** At the start of each future briefing, check if pipeline.cst exists
in fpga/constraints/. If it does not, re-escalate .cst as the unconditional #1 task.
Once .cst is confirmed synthesized with positive slack, promote matched filter to CRITICAL.

[[project-schedule-risks]]
