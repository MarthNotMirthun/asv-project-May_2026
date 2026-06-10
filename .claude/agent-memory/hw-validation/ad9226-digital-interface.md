---
name: ad9226-digital-interface
description: AD9226 has a SEPARATE digital output driver supply (DRVDD) that can be set to 3.3V independently of the 5V AVDD analog supply — eliminates level shifting to Tang Nano 20K
metadata:
  type: project
---

AD9226 (Analog Devices, 28-lead SSOP) has THREE supply domains, not two:
- AVDD (pin 26) = analog supply, must be 5V
- DRVDD (pin 28) = digital OUTPUT DRIVER supply, can be **3.0V or 5V independently**
- DRVSS (pin 27) = digital driver ground

With DRVDD = 3.0-3.3V:
- VOH = 2.95V @ IOH 50uA, 2.80V @ IOH 0.5mA
- VOL = 0.05V @ 50uA, 0.4V @ IOL 1.6mA
- These levels are SAFE for Tang Nano 20K 3.3V LVCMOS inputs (VIH ~2.0V, abs max 3.3V+0.3)

**Why:** CLAUDE.md line 154 says "AVDD and DVDD must both be 5V" — this is WRONG/incomplete. Datasheet confirms DRVDD is a separate rail meant exactly to accommodate 3V logic families.

**How to apply:** Wire AVDD=5V, DRVDD=3.3V (from Tang Nano 3.3V rail or onboard regulator). Then D[11:0], OTR connect DIRECTLY to Tang Nano GPIO — NO level shifter needed at 65MSPS. A high-speed parallel level shifter at 65MSPS would be a showstopper otherwise.

ENCODE input: VIH spec is 2V to DRVDD. Tang Nano 3.3V LVCMOS VOH (~3.0-3.3V) drives ENCODE fine. Keep ENCODE and DRVDD referenced to same domain.

tOD (output data valid delay from ENCODE rising edge) with DRVDD=3V, CL=20pF: **3.5ns min to 7ns max** (confirmed datasheet). FPGA must latch D[11:0] AFTER tOD has elapsed — at 3.375MHz ENCODE (296ns period) this is trivially met; latch on the NEXT system-clk edge after the ENCODE edge, never combinationally on the ENCODE edge itself.
Pipeline/data latency = **7 ENCODE cycles** (datasheet, Rev B) — NOT 3. Any RTL aligning capture to 3 cycles latches the wrong conversion.
OTR truth table (datasheet Table V): input >= +FS -> data=1111_1111_1111 (0xFFF), OTR=1; input < -FS -> data=0000_0000_0000 (0x000), OTR=1; in-range -> OTR=0. NO mid-scale clamp. Clamping to 0x7FF on OTR destroys saturated-ping peak energy.

OUTPUT CODING FORMAT: AD9226 default at D[11:0] is **straight OFFSET BINARY** (0x000=-FS, 0x800=mid/0V, 0xFFF=+FS). A DFS/MODE pin (SSOP pin 22 region) can select twos complement, but the default and the project wiring is offset binary. To get signed twos-complement for a signed DSP datapath, **invert the MSB only**: {~adc_data[11], adc_data[10:0]}. Confirmed: "twos complement is identical to offset binary with the MSB complemented" (Analog Devices EngineerZone). The proposed adc_interface.v MSB-flip fix is therefore CORRECT. cic_decimator.v declares din as `signed` — it REQUIRES this conversion upstream or every sample carries a +2048 DC offset that the CIC's R^N=512 DC gain amplifies massively.

Source: analog.com/media/en/technical-documentation/data-sheets/ad9226.pdf

Related: [[claudemd-corrections]]
