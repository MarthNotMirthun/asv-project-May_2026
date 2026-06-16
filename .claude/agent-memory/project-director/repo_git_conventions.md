---
name: repo-git-conventions
description: Actual GitHub remote, active branch, and commit-hygiene observations for the ASV project repo
metadata:
  type: reference
---

GitHub remote (origin): https://github.com/MarthNotMirthun/asv-project-May_2026.git
Active working branch: **main** (NOT master — an initial stale snapshot may show master).

**Why:** Future sync checks must compare against origin/main on this exact remote.

**How to apply:** When auditing GitHub sync, run `git log`/`git status`/`git diff origin/main`
live — do not trust the conversation's opening git-status snapshot, which has been observed
stale (showed everything untracked when work was in fact committed).

Hygiene note observed 2026-06-10: compiled iverilog sim binaries (`fpga/sim/out_*.out`)
are tracked in the repo. `.gitignore` only excludes `fpga/sim/out.out`, not the `out_*.out`
variants. These are build artifacts and ideally should be gitignored, not committed.
