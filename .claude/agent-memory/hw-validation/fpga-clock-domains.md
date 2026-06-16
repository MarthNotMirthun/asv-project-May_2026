---
name: fpga-clock-domains
description: ASV FPGA pipeline runs entirely on one 27MHz clock domain; ENCODE is FPGA-generated, so no foreign-clock CDC / 2-FF synchronizer is needed
metadata:
  type: project
---

The Tang Nano 20K FPGA pipeline (adc_interface, cic_decimator, fir_filter_bank1, fir_filter_bank2, uart_tx) is **single clock domain — 27MHz `clk` only**. There is NO second clock crystal and NO foreign async clock entering the fabric.

- adc_clk (AD9226 ENCODE, 3.375MHz) is GENERATED inside adc_interface by dividing the 27MHz clk (toggle every CLK_DIV_HALF=4). It is an output, not an input clock.
- adc_interface captures D[11:0] on the system-clock edge AFTER an ENCODE rising-edge detect (rising-edge-detect FF pair on adc_clk), never combinationally on the ENCODE edge. This is the correct synchronous capture; AD9226 tOD (3.5-7ns) is trivially met at the 296ns ENCODE period.
- Therefore: do NOT flag "missing 2-FF synchronizer" on this pipeline. The only real async boundary is FPGA tx -> Pi /dev/ttyAMA0, which the Pi UART re-syncs at the start bit.

OTR caveat: sample_otr is correctly aligned at adc_interface output, but cic_decimator and both FIR banks have NO otr port — the over-range FLAG is dropped after the first stage (saturated data 0xFFF/0x000 still flows). Whether the matched filter needs the flag is a dsp-signal-validator decision.

Voltage/level chain (all 3.3V LVCMOS33, no level shifters anywhere): AD9226 DRVDD=3.3V -> FPGA GPIO; FPGA tx 3.3V -> Pi 3.3V UART RX.

Related: [[ad9226-digital-interface]], [[tang-nano-20k-pins]]
