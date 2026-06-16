# HW Validation Memory Index

- [AD9226 Digital Interface](ad9226-digital-interface.md) — DRVDD is a SEPARATE supply; set to 3.3V for direct Tang Nano connection, no level shifting
- [ESP32 GPIO Limits](esp32-gpio-limits.md) — ESP32 NOT 5V tolerant, abs max 3.6V on pins; 5V sources need level shifting
- [L298N Logic Inputs](l298n-logic-inputs.md) — VIH 2.3V min, needs Vss 5V logic supply; 3.3V GPIO drives it fine
- [CLAUDE.md Corrections](claudemd-corrections.md) — confirmed datasheet conflicts (AD9226 latency=7 not 3, OTR codes, DRVDD)
- [Tang Nano 20K Pins](tang-nano-20k-pins.md) — 27MHz clock is PIN 4 not 52; pin 17 reserved; LVCMOS33
- [Tang Nano 20K Headers](tang-nano-20k-headers.md) — full verified J5/J6 20-pin header pinout; Bank5 pins 25-31 are cleanest GPIO for parallel bus
- [FPGA Clock Domains](fpga-clock-domains.md) — whole pipeline is single 27MHz domain; ENCODE is FPGA-generated; no CDC synchronizer needed
