---
name: project-fpga-build-state
description: FPGA module completion status and key architecture decisions for the ASV acoustic-homing pipeline
metadata:
  type: project
---

FPGA pipeline build progress (as of 2026-06-09, Week 3):
- uart_tx.v — COMPLETE, simulated. 8-byte back-to-back packet verified; inter-byte gap measured at 2 system clocks (~74ns), far under the 234-clock (8.68us) 115200-baud limit.
- adc_interface.v (AD9226) — COMPLETE, simulated. ENCODE-clock architecture, not chip-in-hand yet (AD9226 arrives Jun 14-21). Key timing model below.
- cic_decimator.v — COMPLETE, simulated. R=8, N=3, 28-bit datapath, DC gain R^N=512.
- NEXT: FIR bandpass filter banks (dual: 34-38kHz Buoy1, 42-46kHz Buoy2), 32-tap, Q1.15 coeffs in BSRAM, ~16 HW multipliers each.

**Why:** Resumed an interrupted orchestrator session; these three were the in-flight tasks.
**How to apply:** When asked for "next module," recommend FIR filter banks. Do not rebuild the three completed modules. See [[project-cic-decimation-factor]] for the R=160 vs R=8 correction.

Key timing facts (not in CLAUDE.md, derived from the RTL):
- adc_interface ENCODE (adc_clk) = 27MHz / 8 = 3.375MHz (CLK_DIV_HALF=4). adc_clk period = 8 system clocks.
- adc_interface fills a 3-ENCODE-edge pipeline before streaming; it samples the LIVE bus value at the emit edge (does NOT buffer data through the 3 stages — the 3-edge latency only delays stream start). OTR clamps sample_out to 0x7FF.
- Icarus Verilog is at C:\iverilog\bin\iverilog.exe and vvp.exe (NOT on PATH — use full paths).
