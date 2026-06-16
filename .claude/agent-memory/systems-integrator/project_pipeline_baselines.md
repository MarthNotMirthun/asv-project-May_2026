---
name: project-pipeline-baselines
description: Confirmed as-built FPGA pipeline facts (sample rate, resource totals, latency, data formats) verified against source June 2026
metadata:
  type: project
---

As-built FPGA pipeline facts, verified by reading source files (not CLAUDE.md, which has stale numbers).

**Sample-rate chain (CONFIRMED):** 27MHz sys clk -> adc_interface ENCODE = 27/8 = 3.375MHz -> CIC R=8 -> 421.875 kSPS FIR input. CLAUDE.md still says "~400kSPS, factor ~160" in the pipeline prose — that prose is STALE. The Pi range conversion MUST divide ToF cycles by 421875, not 400000 (~5% error otherwise).

**Data formats at boundaries (CONFIRMED):**
- adc_interface.sample_out: signed two's-comp 12-bit via MSB-invert {~d[11],d[10:0]} (adc_interface.v:83). Requires AD9226 DFS strap = AVSS.
- cic_decimator.dout: signed-16 INTEGER sample scale (scaled ADC code). NOT Q1.15.
- FIR dout: SAME signed-16 integer sample scale (coeffs Q1.15 applied as fractional gain ~0.20). FIR header comments at line 49 mislabel this as "Q1.15-scaled". matched_filter reference chirp must be stored in integer scale, not Q1.15.

**Resource running total (5 modules, CONFIRMED):** ~2/48 multipliers (FIRs use sequential 1-MAC time-shared, NOT the 16-parallel CLAUDE.md budgets), 0/46 BSRAM, ~570/20,736 LUT4. Big consumers still ahead: 2x matched_filter (800-tap) + reference chirps (2x800x16b = 25.6Kb -> BSRAM).

**Latency (CONFIRMED, steady state):** adc_interface 7 ENCODE = 56 sys clk = 2.07us; CIC 1 clk; FIR ~35 clk = 1.30us; matched_filter window ~1.896ms (800 samp @421.875kSPS); uart_tx ~694us/packet. End-to-end well under 100ms real-time homing budget.

**OTR routing (UPDATED 2026-06-12 — NOW WIRED through FIR):** adc_interface.sample_otr -> cic_decimator otr_in/otr_out (OR-latched across R=8 window, cic_decimator.v:29,32) -> both FIR banks otr_in/otr_out (OR across MAC window OR'd with clamp_fired, fir_filter_bank1.v:49,52). Chain is structurally complete adc->cic->FIR. STILL OPEN: matched_filter and peak_detector do not exist yet and MUST carry otr forward, and uart_tx packet has no dedicated quality bit yet (only snr byte) — routing of otr into the packet is an unresolved design decision.

**Integration not yet wired:** No top-level pipeline module exists. fir_test_top.v is a throwaway timing harness (delete before final) and its instantiation is STALE — missing the new otr_in/otr_out ports added to FIR (will fail to elaborate). matched_filter, peak_detector, top-level integration, and ROS2 fpga_uart_node all NOT YET WRITTEN — so UART-packet-vs-parser cross-check is forward-looking, not verifiable yet.

**adc_interface.cst pin block (RESOLVED 2026-06-13):** Previous "contiguous 25-41" block was WRONG — pins 32-39 are RGB-LCD-FPC-only, not header GPIO. Current file uses verified J5/J6 header pads: adc_data[11:0]=73,74,75,85,77,27,28,25,26,29,30,31; otr=80; adc_clk=76. hw-validation (2026-06-13) confirmed against Sipeed schematic rev 1.22 + pinlabel.png: every pin exists, all LVCMOS33, zero collisions with uart_tx.cst, clk(4)/rst_n(88) correctly omitted. adc_interface.cst is now COMPLETE. CLAUDE.md still lists it "NOT YET WRITTEN" — stale, needs docs-updater.

**AD9226 DFS strap:** dsp-validator notes DFS pin must be tied AVSS (not AVDD). If DFS=AVDD the part already outputs two's complement, and adc_interface.v:83 MSB-invert would DOUBLE-convert -> +2048 DC offset -> CIC integrator runaway. Hardware bring-up check.
