---
name: project-hub-v3-build
description: ASV Hub v3 build history — what was in v3 at each revision, data model decisions, and known feature gaps
metadata:
  type: project
---

The hub app lives at hub/asv_hub_v3.html. It is a single-file offline-first PWA (169KB as of June 2026).

**Why:** Portfolio project management tool for Mirthun's GPS-denied acoustic homing catamaran ASV, deadline August 10 2026.

**How to apply:** Always build v3 in-place; do not create v4 unless explicitly asked. Migrations must auto-merge new default content into existing localStorage state.

## localStorage Key Schema

- `asv_state_v3` — main state JSON: `{ config, tasks, parts, learning, logs, learnedConcepts }`
  - `config`: `{ startDate, deadline, weekOverride, weekStatuses, projectStatus, notificationsEnabled }`
  - `tasks[]`: `{ id, text, tag, tagColor, priority, done, week, group }`
  - `parts[]`: `{ id, name, detail, status }` — status: arrived/owned/ordered/pending
  - `learning[]`: `{ id, emoji, title, phase, week, weekNum, body }` — weekNum is integer for filtering
  - `logs[]`: `{ id, date, cat, text }`
  - `learnedConcepts[]`: array of concept id strings
- `asv_audits` — weekly audit array: `[{ id, week, date, status:{technical,cost,career}, done, risks, actions }]`

## v3 Audit Session (June 9 2026) — Changes Made

Starting from a timed-out v3 (1722 lines, 6 concepts), expanded to 2346 lines / 170KB:

1. **Learning tab** — Replaced 6 plain concepts with 16 rich structured concepts spanning W1-W8. Each concept body contains: tldr-box, section-label, theory paragraphs, code-wrap+pre with copy-btn, in-project div (green left border), exercise-box (yellow left border), qa-list with click-to-reveal answers.

2. **Learning filter pills** — Added `#learningFilterPills` element, `filter-pill` CSS class, `learningWeekFilter` state variable, `renderLearningFilterPills()`, `setLearningFilter()`. Pills auto-generate from weekNum values on concepts (W1 through W8).

3. **Today tab** — Added: `todayDateline` (Week 3 Day 2 · June 9 2026 · 62 days), `todayStatsRow` (4-cell grid: tasks done, parts pending, week, days left), `todayCotd` (concept of the day card with Study Now + Mark Learned buttons), `todayTopTasks` (top 3 priority tasks with one-tap checkboxes).

4. **Settings modal** — Added Sync Snapshot button (copies markdown snapshot to clipboard) and Notifications section (toggle enabling 9am/7pm daily browser notifications via setTimeout, test button).

5. **Migration logic** — `loadState()` now auto-merges DEFAULT_STATE learning concepts into saved state: adds missing concepts by id, replaces old plain bodies with rich versions (detected by absence of `tldr-box` class).

## Concept List (16 total, by weekNum)

W1-2: Gowin EDA Timing Constraints (id: l_timing)
W2-3: Verilog Pipelining MAC Stages (id: l_pipeline)
W3-4: AD9226 Parallel ADC Interface (id: l_ad9226)
W3-4: LFM Chirp + Matched Filter Theory (id: l_lfm)
W3-4: Fixed-Point Q1.15 Arithmetic (id: l_qmath)
W4:   CIC Decimation Filter (id: l_cic)
W4-5: FIR Filter Bank Design (id: l_fir)
W5:   Matched Filter Correlator in Verilog (id: l_correlator)
W5:   Peak Detector + TOF Calculator (id: l_peakdet)
W6:   micro-ROS on ESP32 (id: l_microros)
W6:   UART Packet Protocol 8-byte (id: l_uart_proto)
W7:   ROS 2 Node Structure + QoS (id: l_ros2_nodes)
W7:   EKF Dead Reckoning (id: l_ekf)
W7:   PID Homing Controller (id: l_pid)
W8:   Mission State Machine (id: l_statemachine)
W8:   ROS 2 Safety Collision Avoidance (id: l_collision)

## iOS Safari Notes

- No optional chaining (?.); safe
- No dialog element used; modals are div-based with .open class
- Copy buttons use navigator.clipboard with fallbackCopy() for older iOS
- Notifications use standard Web Notifications API (Safari 16.4+ supports it on iOS)
- All touch targets >= 44px
- No CSS gap on flex (uses flex with gap — supported iOS 14.5+, fine for iOS 16 target)
