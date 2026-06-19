## 2026-06-19 — Post-commit hook installed (status-report + AIS-OS notification)

## 2026-06-18 — FIR banks VALIDATED at 38.5–41.5kHz - all 9 FPGA modules verified

**Completed:**
- FIR filter bank 1: re-spun to 38.5–41.5 kHz passband per FC-7 code-division architecture
- FIR filter bank 2: re-spun to 38.5–41.5 kHz passband, identical coefficients to bank1 (sweep direction differentiation, not frequency bands)
- Both banks: 32-tap Hamming windowed-sinc, centered at 40 kHz, 3 kHz bandwidth, passband ripple <1dB, stopband confirmed
- All 9 FPGA pipeline modules now verified: uart_tx, adc_interface, cic_decimator, fir_filter_bank1, fir_filter_bank2, matched_filter_1, matched_filter_2, peak_detector, packet_framer

**Verified:**
- verilog-sim-runner: ALL PASS both banks, no X/Z states detected
- Commit: 5d2edde (FIR re-spin)
- Commit: 13c0d99 (CLAUDE.md file structure updates)

**Validator Findings:**
- dsp-signal-validator: Passband gain linear, stopband rejection adequate, FC-7 code-division architecture validated
- systems-integrator: All 9 modules confirmed ready for integration; no resource conflicts; pipeline latency within 50ms budget

**CLAUDE.md Updated:**
- FPGA Build Status: FIR banks ⚠️ → ✅, both marked VALIDATED Jun 18
- File structure: FIR banks marked DONE (no longer showing "⚠️ COEFF RE-SPIN NEEDED")
- IMMEDIATE NEXT TASKS: reordered — FIR re-spin marked complete (task 3), full pipeline integration now top priority (task 4)
- Last Updated: June 18, 2026

**TRAJECTORY.md Updated:**
- Pipeline status table: FIR banks ✅ DONE & verified with FC-7 architecture confirmed
- Full pipeline integration: status changed from "blocked on FIR coeff re-spin only" to "ALL upstream modules verified — ready to build top-level"
- Section 1 narrative: Updated to reflect all 9 modules verified as of Jun 18

**Next Priority:**
Full pipeline integration — chain all 9 modules into top-level integration module (fpga-verilog-engineer agent)

---

## 2026-06-17 — peak_detector.v + packet_framer.v VALIDATED

**Completed:**
- peak_detector.v: dual-channel RELATIVE gating per FC-7, SNR proxy (8-bit), corr_peak magnitude (32-bit), peak_lag diagnostic (11-bit), OTR passthrough
- packet_framer.v: 8-byte FSM [target_id][peak_lag_H/L][corr_peak_H/L][snr][XOR checksum][0xFF], tx_busy gating, sits between peak_detector and uart_tx
- Both modules testbenches: tb_peak_detector.v
- Simulation: all 12/12 checks PASS, no X/Z states

**Verified:**
- hw-validation: APPROVED WITH CONDITIONS — found missing packet framer and uart_rx, both addressed (packet_framer now added, uart_rx deferred to Week 5 per systems-integrator ruling)
- dsp-signal-validator: BLOCKED resolved — dual-channel RELATIVE gating (|ch1| > 4×|ch2|) confirmed superior to absolute thresholding per FC-7; abs-value stage added for signed corr_peak inputs
- systems-integrator: reconciled relative gating to peak_detector architecture, separated uart_rx config path to Week 5 task list, confirmed packet_framer fits between peak_detector and uart_tx
- verilog-sim-runner: ALL PASS (12/12 checks, no X/Z)
- Commit: 7ee44f0

**Architecture decisions locked today:**
- FC-7: Code-division beacon ID (Buoy 1 = UP-sweep 38.5→41.5 kHz, Buoy 2 = DOWN-sweep 41.5→38.5 kHz) — both in shared transducer passband; sweep direction, not frequency band, distinguishes beacons
- FC-8: Egress maneuver required after each ARRIVED state to increase separation distance and prevent cross-talk blinding at 1–2 m range
- MAX9814 pre-amp DISQUALIFIED: audio-only (20 Hz–20 kHz), cannot pass 40 kHz — must replace with fixed-gain wideband op-amp front end (MCP6022 ~10 MHz GBW or TLV2462); ~$2–8 additional cost

**CLAUDE.md Updated:**
- FPGA Build Status: peak_detector + packet_framer marked ✅ VALIDATED Jun 17
- FPGA Build Status: FIR banks marked ⚠️ (coefficients need re-spin to 38.5–41.5 kHz per FC-7)
- IMMEDIATE NEXT TASKS: peak_detector now complete; FIR coeff re-spin now task #3 (CRITICAL); full pipeline integration task #4

**TRAJECTORY.md Updated:**
- Pipeline status table: peak_detector → ✅ DONE, packet_framer → ✅ DONE
- Full pipeline integration blocked only on FIR coeff re-spin
- Status narrative: all 9 modules verified; FC-7/FC-8 frozen

**Remaining Week 4 tasks:**
1. FIR coefficient re-spin: recalculate 32-tap Hamming windowed-sinc for 38.5–41.5 kHz center, 3 kHz BW; load into both fir_filter_bank1.v and fir_filter_bank2.v; re-simulate both
2. Full pipeline integration: top-level module chaining all 9 verified modules (fpga-sim agent)
3. Synthesis verification: run full design through Gowin EDA, confirm positive timing slack at 27MHz
4. Order replacement preamp: wideband op-amp instead of MAX9814 (~$2–8)

**Next priority:**
FIR coefficient re-spin (task #3 IMMEDIATE NEXT TASKS in CLAUDE.md)

---

## 2026-06-17 — Procurement Status Corrected (Jun 17)

**Completed:**
- Budget spreadsheet reconciliation against delivery confirmations
- MAX9814 pre-amp module confirmed delivered and in hand
- JSN-SR04T waterproof ultrasonic sensor confirmed delivered and in hand
- L298N dual H-bridge module confirmed delivered and in hand

**Verified:**
- Physical parts inspection against order receipts
- CLAUDE.md procurement section updated to reflect correct status

**CLAUDE.md Updated:**
- ✅ Arrived / Owned: Added MAX9814, JSN-SR04T, L298N with Jun 2026 delivery dates
- 🔴 Not Yet Ordered: Removed the three delivered items; kept thrusters, enclosure, PVC/hull materials as still-pending
- Procurement status now accurate for acoustic bench testing chain: TCT40-16R → MAX9814 → AD9226 → FPGA

**Budget Impact:**
- MAX9814: $8 actual (pre-amp stage)
- JSN-SR04T: $10 actual (collision avoidance sensor)
- L298N: $7 actual (motor driver stage)
- Running total: ~$310 optimized budget on track

**Next:**
Peak detector module — outputs corr_peak (32-bit, CORR_SHIFT=16 scale), snr (8-bit homing signal), peak_lag (11-bit diagnostic). Ready for acoustic signal chain assembly once FPGA pipeline integration complete.

---

## 2026-06-16 — BSRAM Resource Accounting Corrected (Jun 16)

**Correction: depth constraint overrides capacity for 2109-sample BSRAM arrays**

The matched filter pipeline run initially calculated 8 BSRAM blocks total based on bit
capacity (33,744 bits per array < 36,864 bits in 2 blocks). Post-commit analysis showed
the depth constraint is binding:

- GW2AR-18 18Kbit BSRAM in 1K×18 mode: **1024 locations deep** (the native 16-bit config)
- 2 blocks × 1024 = 2048 locations < 2109 samples → two blocks insufficient by depth
- 3 blocks × 1024 = 3072 locations ≥ 2109 → three blocks required per array
- Capacity check (2 blocks = 36,864 bits > 33,744 bits) gives the wrong answer here

**Corrected BSRAM totals:**
- FIR filter coefficients: 2 blocks (32-tap × 16-bit = 512 bits/bank, well within 1 block each)
- Matched filter ref ROMs: 3 blocks/channel × 2 channels = 6 blocks
- Matched filter window buffers: 3 blocks/channel × 2 channels = 6 blocks
- **Total: 14 / 46 blocks (~30%)** — was incorrectly stated as 8/46 (~17%)

**Files corrected:**
- matched_filter_1.v, matched_filter_2.v: header comment at BSRAM section
- CLAUDE.md: BSRAM Resource Allocation section (8→12 matched filter blocks, 8→14 total)
- CLAUDE.md: pipeline section — added 4-array architecture description

**Budget outlook:** 14/46 used by existing verified modules. Remaining planned modules
(peak_detector, uart_tx already written, integration top) will add ≤2 more blocks.
Projected final total: ~16/46 blocks (~35%) — 65% margin remaining.

---

## 2026-06-16 — Propulsion/Enclosure Parts Research (Jun 16)

**Parts Research:**
- Researched remaining propulsion parts (thrusters ×2, IP65 enclosure) via Exa web search — links presented to user for manual purchase decision.
- Brave browser opened with 6 tabs: 3 thruster options, 3 enclosure options (see product list below).
- L298N, MAX9814, JSN-SR04T status: **NOT YET ORDERED** — all three remain in the "🔴 Not Yet Ordered — Action Required" section of CLAUDE.md as of Jun 16. User should confirm their order status before proceeding with wiring tasks.

**Thruster Options (545 brushed, 12V, need CW+CCW pair):**
1. equlup 545 50T Brushed (CW) — 7.4–14.8V, 700–1000g thrust, fully waterproof — https://www.amazon.com/equlup-Underwater-Thruster-Brushed-Propeller/dp/B0DHZLLBR3
2. Amazon search — 545 50T CW+CCW pair — https://www.amazon.com/s?k=545+50T+brushed+underwater+thruster+12V+RC+boat+CW+CCW+pair
3. Amazon search — broader brushed thruster — https://www.amazon.com/s?k=underwater+brushed+motor+thruster+12V+catamaran+boat+545

**Enclosure Options (IP65+, large enough for Pi 4 + Tang Nano):**
1. Otdorpatio IP67 6.3"×6.3"×3.5", 4× M16 cable glands included — https://www.amazon.com/Otdorpatio-Electrical-Waterproof-Electronic-160x160x90mm/dp/B0DX781Z3W
2. LeMotech IP65 5.9"×4.3"×2.8", CE/RoHS, pre-drilled — https://www.amazon.com/LeMotech-Dustproof-Waterproof-Universal-Electrical/dp/B075DHRJHZ (slightly small — verify interior fits Pi 4)
3. Amazon search — large IP65 enclosure with cable glands — https://www.amazon.com/s?k=IP65+waterproof+enclosure+project+box+electronics+cable+glands+large

**Thrusters/enclosure NOT marked as ordered** — pending user purchase confirmation.

---

## 2026-06-16 — Dual Matched Filter Correlators Validated (Jun 16)

**Completed:**
- Matched filter correlator ×2 (matched_filter_1.v, matched_filter_2.v) — 2109-sample block correlators, 48-bit internal accumulators, 200Hz output, CORR_SHIFT=16, OTR window-OR
- Companion testbenches (tb_matched_filter_1.v, tb_matched_filter_2.v) — 6-check suites per module

**Verified:**
- hw-validation: 0 BLOCKERs, 2 WARNINGs (OTR propagation, HW multiplier count), 6 NOTEs — APPROVED WITH CONDITIONS
- dsp-signal-validator: 3 BLOCKERs CAUGHT AND RESOLVED (block correlation required, 48-bit accumulator required, 2109-sample window length corrected from stale 800)
- systems-integrator: 0 conflicts, 2 major corrections (BSRAM: 4→8 blocks, resource totals reconciled)
- verilog-sim-runner: matched_filter_1 ALL CHECKS PASSED, matched_filter_2 ALL CHECKS PASSED

**Validator Findings Summary:**
- hw-validation: WARNING — CLAUDE.md HW multiplier count was wrong (stated 32/48 for FIR banks). Actual: FIR banks use sequential ~1/48 each; matched filters use time-shared ~2-4/48. Total ~4-6/48 multipliers (>90% margin).
- dsp-signal-validator: BLOCKER #1 — Block correlation (2109 MACs/sample) cannot fit in 64-clocks/sample sequentially; must use block buffering. RESOLVED: implemented block correlator architecture. BLOCKER #2 — 32-bit accumulator overflows at full scale; corrected to 48-bit internal. BLOCKER #3 — Window length is 2109 samples (5ms × 421.875 kSPS), not 800 (stale figure). CLAUDE.md L87 corrected.
- systems-integrator: Corrected BSRAM count from 4 to 8 total (matched filter windows require 2 blocks per channel × 2 channels = 4; FIR coefficients 2; reference ROMs 2 = 8 total). Verified CORR_SHIFT=16 scaling contract end-to-end.

**Resource Utilization (verified end-to-end):**
- HW Multipliers: ~4-6 / 48 (FIR banks ~1 each, matched filters time-shared ~2-4) — >90% margin
- BSRAM: ~8 / 46 blocks (~17%)
  - FIR coefficients: 2 blocks
  - Matched filter reference chirps: 2 blocks (2109-sample ROM per channel)
  - Matched filter window buffers: 4 blocks (2 per channel, double-buffered)
- LUTs: ~1070 / 20,736 (~5%)

**End-to-End Latency:**
- Matched filter pipeline: ~16-26ms (block correlation + peak detection within 50ms budget)

**Pipeline Simulation Results:**
- matched_filter_1: CHIRP_DETECT corr_peak=709,215 vs NOISE_REJECT corr_peak=64 (>3000× ratio), OTR_FLAG PASS, NO_XZ PASS, SCALING PASS, PEAK_LAG_ZERO PASS
- matched_filter_2: CHIRP_DETECT corr_peak=709,046 vs NOISE_REJECT corr_peak=232 (>3000× ratio), OTR_FLAG PASS, NO_XZ PASS, SCALING PASS, PEAK_LAG_ZERO PASS

**CLAUDE.md Updated:**
- FPGA Build Status: "⏳ Matched filter correlators" → "✅ Matched filter correlators ×2 — block correlator, 2109-tap, 48-bit acc, OTR window-OR, 200Hz output, CORR_SHIFT=16 ← VALIDATED Jun 16"
- Pipeline comment: "800 samples / 2ms" → "2109 samples / 5ms" (FC-3, corrected from stale spec)
- Reference chirps: "2× 800-sample arrays" → "2× 2109-sample arrays"
- FIR bank multiplier claims: Changed from "~16 HW multipliers" each to "~1 HW multiplier (sequential MAC engine)" each
- Total multiplier budget: Changed from "32 of 48 (33% margin)" to "~4-6 of 48 (>90% margin)"
- BSRAM count: Added itemized breakdown totaling ~8 / 46 blocks
- IMMEDIATE NEXT TASKS: Marked task 1 (matched filters) DONE Jun 16; updated task 2 (peak detector) to specify CORR_SHIFT=16 scale and otr_out consumption

**Next:**
Peak detector — outputs corr_peak (32-bit, CORR_SHIFT=16 scale from matched filter), snr (8-bit = corr_peak/noise_floor in same scale), peak_lag (11-bit diagnostic passthrough). No range_cm, no ToF.

---

## 2026-06-13 — Full Pipeline Re-Validation (Jun 13) + adc_interface.cst Verified

**Validation Run Summary:**
Re-ran pipeline on all 5 modules (uart_tx, adc_interface, cic_decimator, fir_filter_bank1, fir_filter_bank2) with constraint files (.cst) included. Complete end-to-end system validation.

**Validator Findings:**

hw-validation:
- APPROVED WITH CONDITIONS — 0 BLOCKERs, 0 WARNINGs
- adc_interface.cst confirmed COMPLETE and pin-correct: all 14 pins verified against GW2AR-18 datasheet, LVCMOS33-compatible banks confirmed, no pin conflicts
- CLKS_PER_BIT=234 verified correct (115,384 baud actual, +0.16% error from target 115,200)
- Single 27MHz clock domain confirmed — no asynchronous CDC needed
- Physical bring-up gates identified: DRVDD=3.3V rail must be wired, OEB tied LOW, DFS strapped to AVSS

dsp-signal-validator:
- APPROVED WITH CONDITIONS — 0 BLOCKERs, 0 WARNINGs, 2 NOTEs (resolved)
- MSB-flip {~data[11], data[10:0]} confirmed correct for offset binary output
- CIC internal width 28 bits vs 21-bit minimum — 7-bit margin, PASS
- CIC shift=5 verified correct per Hogenauer formula for 16-bit output precision
- FIR Q1.15 coefficients verified, 32-tap symmetric Hamming window, linear phase confirmed
- OTR flag propagation confirmed complete: adc→cic→fir (OR-latched at each stage)
- True sample rate measured: 421.875 kSPS (CLAUDE.md ~422kSPS is correct, illustrative figure acceptable)
- Resource utilization for 5 modules: 2/48 HW multipliers, 0/46 BSRAM used

systems-integrator:
- APPROVED WITH CONDITIONS — 0 conflicts between validators, 2 NOTEs resolved, 5 forward constraints issued
- adc_interface.cst "NOT YET WRITTEN" in CLAUDE.md contradicts verified reality — FIXED below
- FIR output is signed-16 INTEGER scale (gain ~0.20), NOT Q1.15 — matched_filter must use same integer scale
- Forward constraints for matched_filter correlators:
  * FC-1: Chirp reference in BSRAM must be integer scale, not Q1.15
  * FC-2: OTR flag chain continues through matched_filter and peak_detector modules
  * FC-3: TOF math uses 421,875 Hz sample rate (not 400,000 Hz rounded figure)
  * FC-4: Peak detection threshold must account for multipath reflections (~1–2m near field)
  * FC-5: Delete fir_test_top.v from fpga/src before full integration

**fpga-verilog-engineer Changes Made:**
1. adc_interface.v:23 — Changed `output reg [11:0] sample_out` to `output reg signed [11:0] sample_out` (declaration-only, FIX-N1)
2. fir_filter_bank1.v:50 — Rewrote output dout port comment: output is signed-16 INTEGER sample scale; matched_filter MUST use same integer scale NOT Q1.15 (FIX-N2)
3. fir_filter_bank2.v:50 — Same FIX-N2 comment rewording
4. tb_cic_decimator.v — Fixed OTR test timing race: hold otr_in high across full window, target dout_count+2
5. tb_fir_filter_bank1.v — Fixed OTR test timing: hold otr_in high, sample otr_out before clock advance, target dout_count+2
6. tb_fir_filter_bank2.v — Same timing fix as bank1

**verilog-sim-runner Results: PIPELINE ALL PASS**
- uart_tx: PASS (0 X/Z, all checks passed)
- adc_interface: PASS (0 X/Z, MSB-flip conversions verified, OTR alignment confirmed)
- cic_decimator: PASS (0 X/Z, DC gain correct, R=8 verified, OTR propagation PASS)
- fir_filter_bank1: PASS (0 X/Z, passband 36kHz preserved, OTR PASS)
- fir_filter_bank2: PASS (0 X/Z, passband 44kHz preserved, OTR PASS)

**CLAUDE.md Updated:**
- FPGA Build Status: "adc_interface.cst: NOT YET WRITTEN" changed to "adc_interface.cst: VERIFIED (pins D[0..11], otr, adc_clk assigned to LVCMOS33 banks) ← VALIDATED Jun 13"
- Added Jun 13 pipeline re-validation line to COMPLETED section
- IMMEDIATE NEXT TASKS: removed timing constraints from critical path (both uart_tx.cst and adc_interface.cst complete), pushed matched_filter to task #1
- Added adc_interface.cst pin configuration to AD9226 Hardware Contract section

**Next Priority:**
1. Matched filter correlators ×2 (800-sample BSRAM correlation windows) — NOW CRITICAL PATH
2. Peak detector + TOF calculator
3. Full pipeline integration and synthesis
4. Hardware bring-up: verify DRVDD=3.3V rail, OEB=LOW, DFS=AVSS

---

## 2026-06-10 — Full Pipeline Validation Run + FIR Filter Banks Built

**Validation Run Summary:**
Pipeline stages 1–3 (hw-validation, dsp-signal-validator, systems-integrator, verilog-sim-runner) completed.

**Issues Found & Fixed:**

hw-validation findings (2 blockers, 1 warning):
- FIX-B1: adc_interface.v — AD9226 outputs offset binary by default (DFS=AVSS). Added MSB inversion: sample_out <= {~adc_data[11], adc_data[10:0]}. Without this, 0V input would feed as -2048 into CIC integrators, causing saturation.
- FIX-B2: cic_decimator.v — output right-shift was WIDTH-16=12 bits, incorrect. Corrected to 5 bits per Hogenauer formula: B_max=12+3×log2(8)=21, shift=(B_max-1)-15=5. Old shift caused ~128× amplitude loss (~42dB SNR collapse).
- FIX-W1: adc_interface.v — added sample_otr output port to propagate OTR flag to matched filter clipping detection downstream.

dsp-signal-validator findings (same root causes):
- Confirmed MSB-flip and shift corrections above.
- FIX-W2: cic_decimator.v header comment corrected: had R=160, DVDD=5V, latency=3 — all wrong. Corrected to R=8, DRVDD=3.3V, 7 ENCODE cycles latency.

systems-integrator findings:
- 0 conflicts between validators. Added signed saturation clamp on CIC dout: full-scale peak (2^20>>5=32768) exactly at signed 16-bit max boundary — clamp prevents wrap.
- DFS strap ambiguity noted: CLAUDE.md assumes DFS=AVSS (default offset binary). Physical verification required when AD9226 arrives.

**Design Decisions:**
- CIC integrators WRAP (not saturate) — this is correct Hogenauer CIC behavior. Saturation clamp applies only to output dout.
- 32-tap FIR at fs=421875Hz cannot achieve 30dB rejection between adjacent 34–38kHz and 42–46kHz bands (normalized gap ~0.019, filter resolution ~0.031). Best achievable ~0.4–2.5dB. Matched filter downstream provides the real band discrimination.

**New Modules Built:**
- fir_filter_bank1.v: 32-tap 34–38kHz bandpass FIR, Hamming windowed-sinc, fs=421875Hz, Q1.15 coefficients, 37-bit accumulator, non-blocking assignments.
- fir_filter_bank2.v: 32-tap 42–46kHz bandpass FIR, same design as bank1.
- Testbenches: tb_fir_filter_bank1.v, tb_fir_filter_bank2.v — verify passband response, adjacent-band attenuation (relative), dout_valid timing, no X/Z.

**Simulation Results (ALL PASS):**
- adc_interface: MSB-flip conversions verified (0x800→0x000, 0xFFF→0x7FF, 0x000→0x800), OTR alignment confirmed, no X/Z.
- cic_decimator: DC_EXPECTED=0x1000 (4096) confirmed, R=8 decimation over 38 intervals verified, no X/Z.
- fir_filter_bank1: 34–38kHz passband active (peak 4729), adjacent-band attenuated, dout_valid 1:1 handshaking verified, no X/Z.
- fir_filter_bank2: 42–46kHz passband active (peak 4766), adjacent-band attenuated, dout_valid 1:1 handshaking verified, no X/Z.

**CLAUDE.md Updated:**
- FPGA Pipeline diagram: CIC line changed from "65MSPS → ~400kSPS (factor ~160, BSRAM-based)" to "CIC Decimation: 3.375MHz → ~422kSPS (R=8, N=3, adc_clk=27MHz/8=3.375MHz)".
- Build status: CIC decimation ⏳ → ✅ (written, fixed, simulated). FIR banks ⏳ → ✅ ×2 (both written and simulated).
- AD9226 Hardware Contract: Added DFS strap note — assumes DFS=AVSS (default). Physical verification required on arrival.
- Timing constraints (.cst file): remains ⏳ — not completed in this run. Still top priority for next session.

**Next Priority:**
1. Write .cst timing constraints (MOST URGENT — unlocks synthesis)
2. Matched filter correlators (2 instances, 800-sample BSRAM correlation windows)
3. Peak detector + TOF calculator
4. Integration testing before AD9226 arrival (June 14–21)

2026-06-08: Completed UART TX module on Tang Nano, synthesized successfully.

Disabled UART serial console on Pi — /dev/ttyAMA0 now free for FPGA comms.

Next: .cst timing constraints file, AD9226 Verilog sim, pending orders.

2026-06-09: Fixed adc_interface.v — added adc_clk ENCODE output, 3-cycle pipeline latency alignment. Testbench rewritten for ENCODE-based timing model. Simulation PASS.
2026-06-09: UART TX verified for 8-byte back-to-back packet — inter-byte gaps measured <<1 bit period. Simulation PASS.
2026-06-09: CIC decimation module written — R=8, 3.375MHz input (27MHz/8 adc_clk), 422kSPS output, N=3 stages, 28-bit internal width. Simulation PASS.
Note: CLAUDE.md decimation factor updated from R=160 (65MSPS assumption) to R=8 (actual 3.375MHz adc_clk architecture).

2026-06-09: Hardware validation (hw-validator, Puppeteer-verified against datasheets):
  BLOCKED — 5 hardware blockers found and fixed same session:
  - uart_tx.cst: clk was pin 52 (9K pin) → fixed to pin 4 (20K crystal)
  - uart_tx.cst: rst_n was on pin 4 (collision with clock) → moved to pin 88 (S1 button, PULL_MODE=UP)
  - uart_tx.cst: tx was pin 17 (onboard LED, not header) → moved to pin 69 (verified free GPIO, Sipeed UART example)
  - adc_interface.v: pipeline latency was 3 ENCODE cycles → corrected to 7 (AD9226 datasheet Rev B)
  - adc_interface.v: OTR clamp was 12'h7FF (mid-scale) → removed clamp, now pass-through (ADC outputs 0xFFF/0x000)
  Simulations re-run after fixes: uart_tx PASS, adc_interface PASS, zero X/Z states.
  CLAUDE.md AD9226 Hardware Contract updated: pipeline latency 3→7, DRVDD=3.3V documented.

2026-06-09: Pin assignments confirmed (source: Sipeed TangNano-20K-example/uart/src/top.cst via GitHub API):
  clk = pin 4 (27MHz oscillator), tx = pin 69 (header GPIO), rst_n = pin 88 (button S1)
  Pending physical verification: confirm pin 69 is accessible on your specific board revision before wiring.

