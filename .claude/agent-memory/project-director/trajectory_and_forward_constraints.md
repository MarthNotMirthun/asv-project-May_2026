---
name: trajectory-and-forward-constraints
description: docs/TRAJECTORY.md is the cross-module compass; FC-1 (integer scale) contradicts a stale Q1.15 line in CLAUDE.md
metadata:
  type: project
---

`docs/TRAJECTORY.md` is the project's living technical compass (created June 15, 2026).
It holds verified pipeline state, FORWARD CONSTRAINTS (FC-1..FC-4), and the physical
verification queue (PV-1..PV-3) for first hardware power-on. Future agents touching the
FPGA pipeline must read its FORWARD CONSTRAINTS section before writing modules.

**Known doc inconsistency to watch:** FC-1 says coefficients/samples are signed-16
INTEGER scale (the format the FIR banks were actually built and verified in on Jun 13).
But CLAUDE.md's "Coding Standards → Verilog" still says "Q1.15 fixed-point." TRAJECTORY.md
FC-1 is authoritative. CLAUDE.md's line should eventually be corrected (docs-updater job,
not a code change) or a future agent reading only CLAUDE.md may reintroduce Q1.15.

**Why:** Two sources of truth disagree on a load-bearing number format; the wrong one
silently breaks the matched filter at the FIR boundary.

**How to apply:** When reviewing direction, verify CLAUDE.md and TRAJECTORY.md still agree
on format/sample-rate; flag drift. Keep Section 1 table and FC list current as modules verify.
See [[user-profile]].
