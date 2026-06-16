---
name: spec-cic-params
description: Actual CIC/pipeline DSP parameters for the ASV FPGA pipeline as built on disk (differ from generic R=160 instructions)
metadata:
  type: project
---

The dsp-signal-validator base instructions cite generic example numbers (R=160, sample rate 406k, shift=5 derived from 34-bit width). The ACTUAL ASV project uses different values — always validate against CLAUDE.md + the files, not the instruction examples.

**Why:** The agent prompt's worked examples (R=160 → 34-bit, etc.) are illustrative, not this project's real config. Using them blindly produces wrong overflow/shift verdicts.

**How to apply:** Confirmed real values (CLAUDE.md + fpga/src on 2026-06-10):
- CIC: R=8, N=3. Bit growth = 12 + N*log2(R) = 12 + 3*3 = 21 bits required. Datapath WIDTH=28 (7 bits margin, OK).
- CIC DC gain = R^N = 8^3 = 512 = 2^9.
- Correct CIC output shift to extract 16-bit: input ±2^11, *2^9 gain = peak bit 20; shift right (20-15)=5. So `>>> 5` is CORRECT; `>>> 12` (WIDTH-16) under-uses range by ~128x.
- Sample rate after decimation: 3.375MHz / 8 = 421.875 kSPS (~422k).
- FIR banks: 32-tap, Q1.15, 16-bit I/O. Bank1 34-38kHz, Bank2 42-46kHz.
- adc_clk (ENCODE) = 27MHz/8 = 3.375MHz. AD9226 pipeline latency = 7 ENCODE cycles.
- AD9226 default straight-binary = offset binary: midscale 0x800, -FS 0x000, +FS 0xFFF. Offset-binary->2's-comp = invert MSB = {~d[11], d[10:0]}. DFS pin selects format (confirmed AD9226 datasheet Rev B).

**Recurring findings (re-validated 2026-06-12; files byte-identical to 2026-06-10 review; AD9226 DFS + Hogenauer B_max formula web-confirmed):**
- OTR death point: adc_interface emits sample_otr, but cic_decimator AND fir_filter_bank1/2 have NO otr port. OTR does not propagate past adc_interface. Recurring WARNING — every new stage added (matched_filter, peak_det) must carry an otr/saturation flag or the saturation event never reaches the SNR/packet.
- FIR datapath format: CIC dout is a signed-16 INTEGER sample (not Q1.15). FIR multiplies integer*Q1.15-coeff then >>>15 = unity-scale fractional-gain filter. Arithmetic is self-consistent, but the FIR header/port comment mislabels dout as "Q1.15" — it's an integer-scale sample. matched_filter reference chirp must be stored in the SAME integer scale, NOT Q1.15, or correlation scaling is wrong.
- FIR acc width OK: sum|coeff| bank1=6640, bank2=6624; worst |acc|=32768*6640=2.18e8 -> 29 bits incl sign; ACCW=38 huge margin. No overflow. FIR gain ~0.20 (6640/32768).
- CIC integrators intentionally wrap (no saturation) = CORRECT required CIC behavior; do NOT flag as missing-saturation. Combs correct wrap in 2's-comp. WIDTH=28 >= B_max=21 so no wrap anyway.
- DON'T blindly apply the generic prompt rule "saturation on every accumulator" to CIC integrators — it would break the filter.

**Re-validation 2026-06-13:** FIR banks now use a synthesizable case-statement `coeff_rom` function (commit 1ca7c83 replaced the old initial-block ROM; fir_test_top.v moved src->sim). Coefficient VALUES unchanged and re-verified numerically: bank1 sum|c|=6640 maxabs=598, bank2 sum|c|=6624 maxabs=587, both symmetric, worst |acc|=2.18e8 = 29 bits incl sign << ACCW=38. CIC/adc/uart src byte-identical. iverilog is NOT installed in the Windows agent environment (not on PATH) — could not re-run sims this session; relied on verilog-sim-runner's prior ALL PASS (2026-06-10) plus static derivation. AD9226 DFS offset-binary/2's-comp select and Hogenauer B_max=Bin+N*log2(R*M) both re-confirmed via web (analog.com, arxiv).
