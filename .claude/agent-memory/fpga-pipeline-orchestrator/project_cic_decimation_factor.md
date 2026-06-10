---
name: project-cic-decimation-factor
description: CIC decimation factor is R=8 (not R=160) due to the ENCODE-clock ADC architecture
metadata:
  type: project
---

The CIC decimator uses decimation factor R=8, NOT the R=160 implied by CLAUDE.md's "65MSPS -> ~400kSPS, factor ~160" text.

**Why:** CLAUDE.md's R=160 figure was written assuming the AD9226 runs at full 65MSPS. The actual architecture drives the AD9226 ENCODE clock at 27MHz/8 = 3.375MHz (manageable for FPGA routing, well above the 46kHz signal max). So 3.375MHz / 8 = 421.875 kSPS, giving R=8 with N=3 stages.
**How to apply:** When discussing the CIC or downstream sample rates, use 3.375MHz input / 422kSPS output / R=8. CLAUDE.md's FPGA Pipeline ASCII diagram still says "factor ~160" — that line is stale; the build-status line and progress.md reflect R=8. If touching FIR/correlator design, the sample rate feeding them is ~422kSPS.
