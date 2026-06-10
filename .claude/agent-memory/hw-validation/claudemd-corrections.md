---
name: claudemd-corrections
description: Confirmed CLAUDE.md spec errors found against datasheets during HW validation reviews
metadata:
  type: project
---

CLAUDE.md spec corrections confirmed against datasheets:

1. **AD9226 supply (line 154)**: CLAUDE.md says "AVDD and DVDD must both be 5V". WRONG.
   Datasheet: AVDD=5V (analog) but DRVDD (digital output driver supply, pin 28) is a SEPARATE rail settable to 3.0-3.3V. Setting DRVDD=3.3V makes D[11:0]/OTR levels directly compatible with Tang Nano 20K — eliminates level shifting entirely. This is the single most important correction; it changes the AD9226→FPGA verdict from "needs level shifting / UNSAFE at 65MSPS" to SAFE.
   **Recommendation: update CLAUDE.md AD9226 Hardware Contract to specify DRVDD=3.3V.**

2. **AD9226 pipeline latency (CLAUDE.md AD9226 Hardware Contract: "pipeline latency = 3 ENCODE cycles")**: WRONG.
   Datasheet (AD9226 Rev B): pipeline/data latency = **7 clock cycles** (data valid 7 ENCODE rising edges after the sampling edge). CLAUDE.md says 3. Any RTL aligning capture to a 3-cycle latency (e.g. adc_interface.v lat_count 1->3) will latch the WRONG conversion. **Recommendation: update CLAUDE.md to 7 cycles.**

3. **AD9226 OTR / out-of-range output code**: OTR is registered with same 7-cycle latency as data (correct in CLAUDE.md). But the output code on over-range is NOT a mid-scale clamp. Datasheet OTR truth table: input > +FS -> OTR=1, data = 1111_1111_1111 (0xFFF); input < -FS -> OTR=1, data = 0000_0000_0000 (0x000). A clamp to 12'h7FF (mid-scale 2047) is incorrect and corrupts saturated samples — destroys matched-filter peak energy on loud pings.

See [[ad9226-digital-interface]].
