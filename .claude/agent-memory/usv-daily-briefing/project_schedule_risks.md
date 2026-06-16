---
name: project-schedule-risks
description: Recurring schedule risks and blockers observed across briefing sessions
metadata:
  type: project
---

**FPGA displacement pattern — confirmed through Week 4 Day 2:**
The .cst constraints file was the #1 carryover task for four consecutive sessions
(W2 + W3D1 + W3D2 + W3D3) before being resolved on 2026-06-13.
matched_filter_correlator.v is now the unconditional #1 task and has NOT been started
as of 2026-06-16 (Week 4 Day 2). This is the second distinct critical-path item
to carry over past its target start week.

The pattern: FPGA work is acknowledged as #1, then displaced by "quick" tasks
(Pi setup, parts ordering, Amazon carts, testbench fixes). Result: carryover sessions.

**Why:** Each "quick" task feels bounded and achievable. FPGA Verilog is open-ended
and intellectually demanding. The displacement is predictable.

**How to apply:** In every briefing from Weeks 3-6:
- FPGA matched filter / peak_detector / pipeline integration must be CRITICAL, always.
- Never demote FPGA modules to TODAY or IF TIME during Weeks 3-6.
- If matched_filter.v does not exist by 2026-06-16 (Week 4 Day 2), escalate to RED.
- Once matched_filter.v simulates clean, peak_detector is the new #1.

**Parts ordering delay — persistent risk:**
As of 2026-06-13, 5 critical parts are still unordered:
- Brushed DC 545 12V underwater thrusters x2 — gates Week 6 motor testing
- L298N dual H-bridge module — gates Week 6 motor testing
- MAX9814 AGC pre-amp module — gates full signal chain bench test after AD9226 arrives
- JSN-SR04T waterproof ultrasonic sensor — gates collision avoidance (Week 7)
- IP65 waterproof electronics enclosure + M12 cable glands — gates hull integration (Week 8)

Amazon domestic: 3-7 day lead time.
Ordered Jun 14 = arrive Jun 17-21 (within Week 4).
Not ordered by Jun 22 = flag thruster arrival as hard RED schedule risk for Week 6.

**AD9226 arrival:**
Chip expected 2026-06-14 to 2026-06-21. Today (Jun 14) is Day 1 of window.
adc_interface.v and adc_interface.cst are both complete and waiting.
Critical physical check on arrival: confirm DFS=AVSS (not AVDD) before power-on.
Do NOT apply AVDD=5V before DRVDD=3.3V is wired and OEB=LOW.

**Timeline RED/YELLOW thresholds (updated Jun 16):**
- matched_filter_correlator.v not simulating by Jun 21 (Week 4 end) -> Technical RED, milestone miss
- 5 Amazon parts not ordered by Jun 22 -> Cost/Schedule RED
- peak_detector.v not started by Jun 23 (Week 5 Day 2) -> Technical YELLOW escalation

[[project-milestones]]
