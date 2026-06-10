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
