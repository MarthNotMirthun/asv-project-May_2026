---
name: project-milestones
description: Completed FPGA/Pi milestones and their dates, plus pending critical tasks — tracks what is actually done vs what CLAUDE.md planned
metadata:
  type: project
---

As of 2026-06-16 (Project Day 23, Week 4 Day 2):

**Completed:**
- FPGA: Gowin EDA installed, basic combinational + clocked logic confirmed
- FPGA: uart_tx.v written and synthesized onto Tang Nano (2026-06-08)
- FPGA: adc_interface.v — MSB-flip, OTR port, ENCODE output, 7-cycle pipeline latency (2026-06-09, validated 2026-06-10)
- FPGA: cic_decimator.v — R=8, shift=5, saturation clamp, sim PASS (2026-06-09, validated 2026-06-10)
- FPGA: fir_filter_bank1.v + fir_filter_bank2.v — 32-tap Hamming windowed-sinc, signed-16 INTEGER scale, sim PASS (2026-06-10)
- FPGA: uart_tx.cst — written and verified (2026-06-13)
- FPGA: adc_interface.cst — all 14 pins verified LVCMOS33-compatible, no bank conflicts (2026-06-13)
- Full pipeline re-validation: hw-validator, dsp-signal-validator, systems-integrator, verilog-sim-runner — ALL PASS (2026-06-13)
- Pi: Ubuntu 24.04.4 LTS + ROS 2 Jazzy installed and verified
- Pi: /dev/ttyAMA0 UART serial console disabled — port free for FPGA comms (2026-06-08)
- Pi: SSH, colcon, rosdep, heatsinks, avahi-daemon all working
- Parts: AD9226 ARRIVED June 8, 2026 — in hand, pre-power checklist pending (DFS=AVSS, DRVDD=3.3V, OEB=LOW)
- Parts: LiPo x2, charger, fuses, MPU-6050, TCT40 transducer pack, ESP32 x2 — all arrived
- Pin assignments confirmed: clk=pin4, tx=pin69, rst_n=pin88

**Critical blocker RESOLVED (Jun 13):**
- .cst timing constraints: uart_tx.cst and adc_interface.cst BOTH COMPLETE as of 2026-06-13
  This was the #1 carryover task for 4 consecutive sessions (W2 + W3D1 + W3D2 + W3D3).
  It is now resolved. The matched filter is now the unconditional #1 task.

**Pending (not yet done as of Week 4 Day 2 — June 16):**
- matched_filter_correlator.v — NOT STARTED (CRITICAL PATH, hardest module)
  Still not started entering Week 4 Day 2. This is now escalated.
  Gates: peak_detector.v, TOF calculator, full pipeline integration.
  Must be functionally complete and simulating by Jun 21 (Week 4 end) or technical goes RED.
- peak_detector.v + TOF calculator — not started
- Full pipeline integration (AD9226 -> CIC -> FIR -> matched filter -> UART) — not started
- Gowin EDA synthesis run on full pipeline — not run yet (both .cst files now in place)
- 5 Amazon orders still pending: thrusters x2, L298N, MAX9814, JSN-SR04T, IP65 enclosure
  Must be ordered June 16 to arrive within Week 4. Not ordered by Jun 22 = hard RED risk.
- Home Depot PVC materials run not yet scheduled

**Why this matters:** All simulation modules are validated and .cst files complete.
The matched filter is the sole remaining FPGA blocker before full pipeline integration.
Week 5 milestone (dual matched filter banks) is at risk if Week 4 does not produce
both matched filter instances simulating clean.

**How to apply:** At the start of each future briefing, check fpga/src/ for
matched_filter_correlator.v. If it does not exist, matched filter start is CRITICAL #1.
Once it exists and simulates clean (0 X/Z, correlation peak visible), promote
peak_detector + TOF to CRITICAL.

[[project-schedule-risks]]
