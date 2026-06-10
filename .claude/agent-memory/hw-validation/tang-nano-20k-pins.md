---
name: tang-nano-20k-pins
description: Confirmed Tang Nano 20K (GW2AR-18 QN88) FPGA pin assignments for .cst constraints
metadata:
  type: project
---

Tang Nano 20K (GW2AR-18, QFN88) confirmed pin facts from Sipeed wiki + official LED example:

- **27MHz onboard crystal oscillator = FPGA PIN 4 (PIN04)**. Confirmed by Sipeed wiki ("input pin of crystal oscillator is PIN04") and the official led.md example. Any clock constraint MUST be `IO_LOC "clk" 4;`.
- **LED0 = PIN15.** Onboard LEDs are around pins 15-16 and up.
- **PIN 52 is NOT the 27MHz clock on the Tang Nano 20K.** The `IO_LOC "clk" 52` convention seen in many tutorials is for the **Tang Nano 9K**, a different board. Do not copy 9K constraints onto the 20K.
- **PIN 17 = onboard LED sys_led[2]** (CONFIRMED). Pins 15-20 are the six onboard LEDs (LED0=15). Pin 17 is NOT a free header GPIO — assigning a UART tx or any external signal here drives an onboard LED, not a pin reachable by the Pi. Always BLOCKER for any inter-board signal.
- **Buttons S1/S2 = pins 88/87**, PULL_MODE=DOWN. Good candidates for rst_n if a debounced button reset is wanted (but they read HIGH when pressed with pulldown — active-low rst_n on a pulldown button is backwards; needs PULL_MODE=UP or invert).
- I/O standard: **LVCMOS33** is correct for the 3.3V GPIO banks.
- Free user GPIO for inter-board UART: use the two 20-pin breadboard headers (e.g. pins in the 25-30s / 70s range broken out to headers), NOT pins 4 (xtal), 15-20 (LEDs), 87-88 (buttons), 17.

How to apply: when reviewing any Tang Nano 20K .cst, verify clk is on pin 4, not 52. If clk is on 52 and rst_n on 4, the design will get no oscillator on clk and the reset line will be fighting the crystal net — BLOCKER.
