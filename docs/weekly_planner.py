#!/usr/bin/env python3
"""
ASV Weekly Planner
Reads CLAUDE.md and docs/TRAJECTORY.md, outputs a structured weekly plan
in the same format as the daily briefing email.

Usage:
    python docs/weekly_planner.py                    # writes docs/weekly_plan.txt + stdout
    python docs/weekly_planner.py --stdout-only      # stdout only
    python docs/weekly_planner.py --out PATH         # custom output path
"""

import re
import sys
import argparse
from datetime import date, timedelta
from pathlib import Path

# ── project constants ──────────────────────────────────────────────────────────

PROJECT_START = date(2026, 5, 25)
DEADLINE      = date(2026, 8, 10)

WEEK_PHASES = {
    1:  "Foundation + ordering",
    2:  "AD9226 interface + hull start",
    3:  "Timing constraints + AD9226 sim",
    4:  "CIC decimation + single FIR bank",
    5:  "Dual matched filter banks",
    6:  "ESP32 micro-ROS + buoy firmware",
    7:  "ROS 2 nodes + PID homing",
    8:  "Mission state machine + display",
    9:  "Pool test #1",
    10: "Pool test #2 + tuning",
    11: "Polish + demo video",
}

MILESTONES = {
    5:  "Dual matched filter banks complete",
    9:  "Pool Test #1",
    10: "Pool Test #2",
    11: "Demo deadline — Aug 10",
}

BOX_WIDTH = 64   # total line width including ║ chars
INNER     = BOX_WIDTH - 2

# ── date helpers ───────────────────────────────────────────────────────────────

def day_str(d: date) -> str:
    return f"{d.strftime('%b')} {d.day}"

def fmt_date(d: date) -> str:
    return f"{d.strftime('%b')} {d.day}, {d.year}"

def fmt_range(start: date, end: date) -> str:
    if start.month == end.month:
        return f"{start.strftime('%b')} {start.day}–{end.day}, {end.year}"
    return f"{day_str(start)}–{day_str(end)}, {end.year}"

# ── temporal math ──────────────────────────────────────────────────────────────

def compute_temporal(today: date) -> dict:
    elapsed     = (today - PROJECT_START).days
    week_num    = elapsed // 7 + 1
    project_day = elapsed + 1
    days_left   = (DEADLINE - today).days
    week_start  = PROJECT_START + timedelta(weeks=week_num - 1)
    week_end    = week_start + timedelta(days=6)

    next_ms = next(
        (f"Week {w} — {m}" for w, m in sorted(MILESTONES.items()) if w >= week_num),
        None,
    )
    return {
        "today":          today,
        "week_num":       week_num,
        "project_day":    project_day,
        "days_left":      days_left,
        "week_start":     week_start,
        "week_end":       week_end,
        "phase":          WEEK_PHASES.get(week_num, "Unknown phase"),
        "next_milestone": next_ms,
    }

# ── markdown parsing ───────────────────────────────────────────────────────────

def strip_escapes(text: str) -> str:
    return re.sub(r"\\([#\-\[\]\(\)\*\|\.!])", r"\1", text)

def extract_section(text: str, header_re: str, stop_res: list[str] | None = None) -> str:
    m = re.search(header_re, text, re.IGNORECASE | re.MULTILINE)
    if not m:
        return ""
    start = m.end()
    stops = stop_res or [r"^#{1,4}\s", r"^---\s*$"]
    end   = len(text)
    for pat in stops:
        sm = re.search(pat, text[start:], re.MULTILINE)
        if sm and (start + sm.start()) < end:
            end = start + sm.start()
    return text[start:end].strip()


def parse_claude_md(path: Path) -> dict:
    raw  = path.read_text(encoding="utf-8")
    text = strip_escapes(raw)

    # Last updated
    m = re.search(r"Last Updated:\s*(.+)", text)
    last_updated = m.group(1).strip() if m else "unknown"

    # FPGA build status — ✅ and ⏳ bullet lines
    build_sec     = extract_section(text, r"### FPGA Build Status")
    fpga_done     = re.findall(r"✅\s+(.+)", build_sec)
    fpga_pending  = re.findall(r"⏳\s+(.+)", build_sec)

    # Immediate next tasks — numbered items (first line of each)
    tasks_sec  = extract_section(text, r"IMMEDIATE NEXT TASKS")
    next_tasks = re.findall(r"^\d+\.\s+(.+)", tasks_sec, re.MULTILINE)

    # Unordered parts — anchor to the ### section header to avoid matching
    # inline "NOT YET ORDERED" text inside the Propulsion hardware block
    unordered_sec   = extract_section(text, r"^###.*Not Yet Ordered")
    unordered_parts = re.findall(r"^-\s+(.+)", unordered_sec, re.MULTILINE)

    # Weekly timeline table rows
    timeline_sec = extract_section(text, r"## WEEKLY TIMELINE", [r"^---\s*$", r"^##\s"])
    timeline     = []
    for row in re.finditer(r"\|\s*(\d+)\s*\|\s*([^|]+)\|\s*([^|]+)\|\s*([^|]+)\|", timeline_sec):
        wk, dates, phase, status = (g.strip() for g in row.groups())
        timeline.append({"week": int(wk), "dates": dates, "phase": phase, "status": status})

    return {
        "last_updated":  last_updated,
        "fpga_done":     fpga_done,
        "fpga_pending":  fpga_pending,
        "next_tasks":    next_tasks,
        "unordered":     unordered_parts,
        "timeline":      timeline,
    }


def parse_trajectory_md(path: Path) -> dict:
    empty = {"fc": [], "pv": [], "critical_path": "", "pipeline": []}
    if not path.exists():
        return empty
    raw  = path.read_text(encoding="utf-8")
    text = strip_escapes(raw)

    # FC items — first complete paragraph of each FC-N block (up to first blank line)
    fc = []
    for m in re.finditer(r"### (FC-\d+)[^\n]*\n(.*?)(?=###|\Z)", text, re.DOTALL):
        label = m.group(1)
        body  = m.group(2).strip()
        # Take lines until the first blank line = first paragraph
        para_lines = []
        for line in body.splitlines():
            if not line.strip():
                break
            para_lines.append(line.strip())
        # Strip markdown bold markers for clean plain-text output
        para = re.sub(r"\*\*([^*]+)\*\*", r"\1", " ".join(para_lines))
        para = re.sub(r"`([^`]+)`", r"\1", para)
        fc.append((label, para))

    # PV table rows
    pv_sec = extract_section(text, r"## 3\.", [r"^##\s"])
    pv = []
    for row in re.finditer(r"\|\s*(PV-\d+)\s*\|\s*([^|]+)\|\s*([^|]+)\|\s*([^|]+)\|", pv_sec):
        num, check, required, _ = (g.strip() for g in row.groups())
        required = re.sub(r"\*\*([^*]+)\*\*", r"\1", required)
        pv.append((num, check, required))

    # Critical path — first substantive sentence of section 4
    cp_sec = extract_section(text, r"## 4\.", [r"^##\s"])
    cp_lines = [l.strip() for l in cp_sec.splitlines() if l.strip() and not l.startswith("#")]
    cp = cp_lines[0] if cp_lines else ""

    # Pipeline status rows from section 1 — permissive module-name match so
    # rows like `fir_filter_bank1` (34–38 kHz) are captured in full
    pipe_sec = extract_section(text, r"## 1\.", [r"^##\s"])
    pipeline = []
    for row in re.finditer(r"\|\s*([^|]+?)\s*\|\s*([✅⏳][^|]*)\|\s*([^|]+)\|", pipe_sec):
        module, status, notes = (g.strip() for g in row.groups())
        # Skip separator rows (|---|---|---|)
        if re.fullmatch(r"[-: ]+", module):
            continue
        # Strip backticks from module name for readability
        module = re.sub(r"`([^`]+)`", r"\1", module)
        pipeline.append({"module": module, "status": status, "notes": notes})

    return {"fc": fc, "pv": pv, "critical_path": cp, "pipeline": pipeline}

# ── status inference ───────────────────────────────────────────────────────────

def infer_status(t: dict, claude: dict) -> dict:
    n_pending   = len(claude["fpga_pending"])
    n_unordered = len(claude["unordered"])

    tech    = "GREEN" if n_pending == 0 else ("YELLOW" if n_pending <= 2 else "RED")
    procure = "RED"   if n_unordered >= 5 else ("YELLOW" if n_unordered >= 2 else "GREEN")
    sched   = "GREEN" if t["days_left"] > 56 else ("YELLOW" if t["days_left"] > 28 else "RED")
    overall = "RED" if "RED" in (tech, procure, sched) else ("YELLOW" if "YELLOW" in (tech, procure, sched) else "GREEN")
    return {"overall": overall, "tech": tech, "procure": procure, "sched": sched}

# ── text layout ────────────────────────────────────────────────────────────────

def rule() -> str:
    return "━" * BOX_WIDTH

def box_top() -> str:
    return "╔" + "═" * INNER + "╗"

def box_bot() -> str:
    return "╚" + "═" * INNER + "╝"

def box_row(text: str = "") -> str:
    return "║" + text.center(INNER) + "║"

def wrap(text: str, width: int, indent: int) -> list[str]:
    pad   = " " * indent
    avail = width - indent
    words = text.split()
    lines, cur = [], ""
    for w in words:
        if cur and len(cur) + len(w) + 1 > avail:
            lines.append(pad + cur.rstrip())
            cur = w + " "
        else:
            cur += w + " "
    if cur.strip():
        lines.append(pad + cur.rstrip())
    return lines

# ── plan builder ───────────────────────────────────────────────────────────────

def build_plan(t: dict, claude: dict, traj: dict) -> str:
    st = infer_status(t, claude)
    out: list[str] = []

    def ln(s: str = "") -> None:
        out.append(s)

    # Header
    ln(box_top())
    ln(box_row("ASV PROJECT — WEEKLY PLAN"))
    ln(box_row(f"WEEK {t['week_num']} OF 11  |  {fmt_range(t['week_start'], t['week_end'])}"))
    ln(box_bot())
    ln()

    # Temporal status
    ln("  TEMPORAL STATUS")
    ln(f"    Week {t['week_num']} of 11  |  Project Day {t['project_day']}  |  {t['days_left']} days until Aug 10")
    ln(f"    Phase: {t['phase']}")
    if t["next_milestone"]:
        ln(f"    Next milestone: {t['next_milestone']}")
    ln()

    # Overall status
    ln(f"  OVERALL STATUS: {st['overall']}")
    pending_count   = len(claude["fpga_pending"])
    unordered_count = len(claude["unordered"])
    ln(f"    Technical:   {st['tech']:<6} — {pending_count} FPGA module(s) still pending")
    ln(f"    Procurement: {st['procure']:<6} — {unordered_count} critical part(s) not yet ordered")
    ln(f"    Schedule:    {st['sched']:<6} — {t['days_left']} days left, {max(0, 11 - t['week_num'])} week(s) remaining")
    ln()

    # This week's tasks
    ln(rule())
    ln(f"  THIS WEEK'S TASKS  (Week {t['week_num']} — from CLAUDE.md)")
    ln(rule())
    ln()

    tasks = claude["next_tasks"]
    if tasks:
        ln("  CRITICAL PATH")
        for line in wrap(f"[ ] {tasks[0]}", BOX_WIDTH, 4):
            ln(line)
        ln()

        if len(tasks) > 1:
            ln("  THIS WEEK")
            for task in tasks[1:]:
                for line in wrap(f"[ ] {task}", BOX_WIDTH, 4):
                    ln(line)
            ln()
    else:
        ln("  (No immediate tasks found in CLAUDE.md — check IMMEDIATE NEXT TASKS section)")
        ln()

    # Forward constraints
    if traj["fc"]:
        ln(rule())
        ln("  FORWARD CONSTRAINTS  (TRAJECTORY.md — every new module must respect these)")
        ln(rule())
        ln()
        for label, para in traj["fc"]:
            for line in wrap(f"{label}: {para}", BOX_WIDTH, 4):
                ln(line)
        ln()

    # Physical verification queue
    if traj["pv"]:
        ln(rule())
        ln("  PHYSICAL VERIFICATION QUEUE  (before first hardware power-on)")
        ln(rule())
        ln()
        for num, check, required in traj["pv"]:
            ln(f"  [ ] {num}: {check}")
            ln(f"        Required: {required}")
        ln()

    # Pipeline status
    ln(rule())
    ln("  FPGA PIPELINE STATUS")
    ln(rule())
    ln()
    rows = traj["pipeline"] or [
        {"module": item, "status": "✅"} for item in claude["fpga_done"]
    ] + [
        {"module": item, "status": "⏳"} for item in claude["fpga_pending"]
    ]
    for row in rows:
        tick = "✅" if "✅" in row["status"] else "⏳"
        ln(f"  {tick}  {row['module']}")
    ln()

    # Procurement
    if claude["unordered"]:
        ln(rule())
        ln("  PROCUREMENT — NOT YET ORDERED  (each gates a downstream week)")
        ln(rule())
        ln()
        for part in claude["unordered"]:
            ln(f"  🔴  {part}")
        ln()

    # Lookahead
    ln(rule())
    ln("  LOOKAHEAD — NEXT 2 WEEKS")
    ln(rule())
    ln()
    found = 0
    for row in claude["timeline"]:
        wk = row["week"]
        if wk in (t["week_num"] + 1, t["week_num"] + 2):
            ms = f"  🎯 {MILESTONES[wk]}" if wk in MILESTONES else ""
            ln(f"  Week {wk:2d} ({row['dates']})  {row['phase']}")
            if ms:
                ln(f"         {ms}")
            found += 1
    if not found:
        ln("  No lookahead data — check WEEKLY TIMELINE table in CLAUDE.md.")
    ln()

    # Footer
    ln("═" * BOX_WIDTH)
    ln(f"  Generated {fmt_date(t['today'])}  |  CLAUDE.md last updated: {claude['last_updated']}")
    ln(f"  Plan saved to docs/weekly_plan.txt")
    ln("═" * BOX_WIDTH)

    return "\n".join(out)

# ── main ───────────────────────────────────────────────────────────────────────

def main() -> None:
    # Task Scheduler and Windows console default to cp1252 — force UTF-8
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")

    ap = argparse.ArgumentParser(description="ASV weekly planner")
    ap.add_argument("--stdout-only", action="store_true", help="Print only, don't write file")
    ap.add_argument("--out", default=None, help="Output path (default: docs/weekly_plan.txt)")
    args = ap.parse_args()

    # Paths relative to this script's location (docs/)
    script_dir   = Path(__file__).resolve().parent
    project_dir  = script_dir.parent
    claude_path  = project_dir / "CLAUDE.md"
    traj_path    = script_dir / "TRAJECTORY.md"

    if not claude_path.exists():
        print(f"ERROR: CLAUDE.md not found at {claude_path}", file=sys.stderr)
        sys.exit(1)

    today    = date.today()
    temporal = compute_temporal(today)
    claude   = parse_claude_md(claude_path)
    traj     = parse_trajectory_md(traj_path)
    plan     = build_plan(temporal, claude, traj)

    print(plan)

    if not args.stdout_only:
        out_path = Path(args.out) if args.out else script_dir / "weekly_plan.txt"
        out_path.write_text(plan, encoding="utf-8")


if __name__ == "__main__":
    main()
