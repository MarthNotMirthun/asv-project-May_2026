---
name: toolchain-iverilog-path
description: Where the Verilog simulator lives on this Windows machine and how to invoke it
metadata:
  type: reference
---

Icarus Verilog is installed at `C:\iverilog\bin\` (binaries `iverilog.exe`, `vvp.exe`). It is NOT on PATH and NOT discoverable by `Get-Command iverilog`.

**Why:** The machine originally had no Verilog simulator at all (only Gowin EDA at `C:\Gowin\Gowin_V1.9.11.03_Education_x64` and `C:\Gowin\Gowin_V1.9.12.01_x64`, which bundles no command-line simulator). Installed via `winget install --id Icarus.Verilog` on 2026-06-09; winget dropped it at the non-standard `C:\iverilog\` root.

**How to apply:** Always invoke the simulator with the absolute path in PowerShell, e.g.
`& "C:\iverilog\bin\iverilog.exe" -o out.out tb.v dut.v; & "C:\iverilog\bin\vvp.exe" out.out`
Do not assume `iverilog` resolves on PATH. Gowin EDA is the synthesis/.cst toolchain; iverilog is the sim toolchain. See [[verified-modules]].
