# FPGA Verilog Engineer — Memory Index

- [Iverilog toolchain path](toolchain-iverilog-path.md) — sim binaries at C:\iverilog\bin (NOT on PATH); use absolute paths
- [Verified modules](verified-modules.md) — uart_tx, adc_interface, cic_decimator, fir_filter_bank1/2 simulated X/Z-clean, with key interface facts
- [FIR selectivity limit](fir-selectivity-limit.md) — 32-tap FIR can't hit 30dB adjacent rejection at fs=421kHz; matched filter does the real selectivity
