---
name: project-schedule-risks
description: Recurring schedule risks and blockers observed across briefing sessions
metadata:
  type: project
---

**Risk pattern confirmed through Week 3 Day 3 (2026-06-10):**
FPGA simulation work is ahead of original plan (CIC + FIR banks + adc_interface all
validated as of 2026-06-10), but synthesis has never been run because the .cst
constraints file remains unwritten. The .cst file was the #1 task in Week 2 and
again on W3D1, W3D2, and W3D3 — four consecutive sessions of carryover.
The matched filter (the hardest component) cannot start until .cst is done.
If .cst is not written by 2026-06-14 (Week 3 end), technical status flips RED.

**Why:** FPGA Verilog work is the hardest component and has been deferred twice
when other tasks (Pi setup, parts ordering, Amazon carts) competed for attention.
The pattern is: FPGA task is acknowledged, then displaced by "quick" infrastructure work.

**How to apply:** In every briefing from Week 3-6, the FPGA .cst / CIC / FIR /
matched filter task chain must be CRITICAL regardless of other open items.
Never demote FPGA work to TODAY or IF TIME during Weeks 3-6. If the .cst file
still does not exist by Week 4 Day 1 (2026-06-15), escalate to RED overall status.

**Parts ordering delay pattern:**
As of 2026-06-10, 5 critical parts are still unordered:
- Brushed DC 545 12V underwater thrusters x2 — gates Week 6 motor testing
- L298N dual H-bridge module — gates Week 6 motor testing
- MAX9814 AGC pre-amp module — gates full signal chain bench test after AD9226 arrives
- JSN-SR04T waterproof ultrasonic sensor — gates collision avoidance (Week 7)
- IP65 waterproof electronics enclosure + M12 cable glands — gates hull integration (Week 8)
Amazon domestic: 3-7 day lead time. If ordered by June 11, arrive by June 18.
If not ordered by 2026-06-14, thruster arrival will compress Week 6 motor integration.
If not ordered by 2026-06-22, flag as a hard RED cost/schedule risk.

**AD9226 arrival window:**
Chip expected 2026-06-14 to 2026-06-21. adc_interface.v is already written and
validated in simulation as of 2026-06-10 — bench testing prep is complete.
DFS pin verification is the critical physical check on arrival (DFS=AVSS assumed).

[[project-milestones]]
