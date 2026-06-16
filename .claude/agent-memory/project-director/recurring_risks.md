---
name: recurring-risks
description: Risks that keep recurring across project-director sessions for the ASV USV project
metadata:
  type: project
---

Recurring patterns observed as project director for the ASV acoustic-homing USV.

**RR-1 — Doc/working-tree drift outpaces commits.** Verified FPGA work gets reflected
in CLAUDE.md / progress.md / TRAJECTORY.md and agent-memory files, but those edits sit
uncommitted for days. On 2026-06-15 the entire Jun 13 validation result (CLAUDE.md,
new TRAJECTORY.md, 7 agent-memory files) was uncommitted while origin/main was in sync
at last commit 62d8e7b (Jun 13). Pattern: code gets committed; *documentation of why*
lags. **Why it matters:** a recruiter reads the commit history; gaps make verified work
invisible. **How to apply:** every session, check `git status` for uncommitted docs and
push a "docs: week N baseline" commit promptly.

**RR-2 — Two weeks of carryover from Weeks 1-2 (partial Foundation/AD9226).** This slack
never got recovered; it compresses the matched-filter window (Weeks 3-6). Watch every
week for whether the matched filter is actually being *started*, not just planned.

**RR-3 — Source-of-truth disagreement (Q1.15 vs signed-16 integer).** CLAUDE.md coding
standards still imply Q1.15 in places; TRAJECTORY.md FC-1 is authoritative (integer scale).
Recurs because two docs describe the same number format. See [[trajectory-and-forward-constraints]].

**RR-4 — FC-4 / fir_test_top.v lifecycle.** fir_test_top.v was added (commit 1ca7c83) then
removed from fpga/src (confirmed absent 2026-06-15), but TRAJECTORY.md FC-4 and CLAUDE.md
still list "delete fir_test_top.v" as a pending integration action. Stale instruction.

**Critical-path mental model (cross-module forward constraints):**
adc_interface → cic_decimator → FIR banks → **matched_filter** → peak_detector/TOF → uart_tx.
The FIR banks' signed-16 INTEGER output (FC-1) is the load-bearing constraint that flows
forward: the matched filter's BSRAM reference chirps MUST be integer scale or the
correlation silently breaks at the FIR→matched-filter boundary. OTR flag (FC-2) must thread
through every new stage. TOF math is locked to 421,875 Hz (FC-3), not 400k/422k approximations.
