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

