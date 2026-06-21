import smtplib
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
from datetime import date
import os
import re

# ── Read briefing ─────────────────────────────────────────────────
briefing_path = os.path.join(os.path.dirname(__file__), 'docs', 'daily_briefing.txt')
try:
    with open(briefing_path, 'r', encoding='utf-8', errors='replace') as f:
        raw = f.read()
except FileNotFoundError:
    raw = ""

# ── Robust section parser (keyword-based, emoji-agnostic) ─────────
def get_section(text, keywords, end_keywords):
    """Find a section by any of its keywords, end at any end_keyword."""
    start_idx = -1
    for kw in keywords:
        idx = text.lower().find(kw.lower())
        if idx != -1:
            # Move to end of that line
            start_idx = text.find('\n', idx)
            if start_idx != -1:
                start_idx += 1
            break
    if start_idx == -1:
        return ""
    end_idx = len(text)
    for ek in end_keywords:
        ei = text.lower().find(ek.lower(), start_idx)
        if ei != -1 and ei < end_idx:
            end_idx = ei
    return text[start_idx:end_idx].strip()

# Section boundaries — plain text keywords, no emoji dependency
temporal = get_section(raw,
    ['TEMPORAL STATUS', 'WEEK STATUS', 'PROJECT DAY'],
    ['OVERALL STATUS', 'TODAY\'S TASKS', 'PARTS &'])

status = get_section(raw,
    ['OVERALL STATUS', 'PROJECT STATUS', 'STATUS:'],
    ["TODAY'S TASKS", 'PARTS &', 'ARRIVALS'])

tasks = get_section(raw,
    ["TODAY'S TASKS", 'DAILY TASKS', 'TASKS FOR TODAY'],
    ['PARTS &', 'ARRIVALS', 'LEARNING CONCEPT'])

parts = get_section(raw,
    ['PARTS & ARRIVALS', 'PARTS AND ARRIVALS', 'PARTS STATUS'],
    ["TODAY'S LEARNING", 'LEARNING CONCEPT', 'TOP 3 RISKS'])

learning = get_section(raw,
    ["TODAY'S LEARNING", 'LEARNING CONCEPT', 'STUDY TODAY'],
    ['TOP 3 RISKS', 'RISKS', 'NEXT 48'])

risks = get_section(raw,
    ['TOP 3 RISKS', 'TOP RISKS', 'RISKS:'],
    ['NEXT 48', '48-HOUR', '48 HOUR'])

next48 = get_section(raw,
    ['NEXT 48-HOUR', 'NEXT 48 HOUR', '48-HOUR ACTIONS', 'NEXT ACTIONS'],
    ['===', '___', 'Briefing saved', 'END'])

# ── Date from header ──────────────────────────────────────────────
date_str = date.today().strftime('%A, %B %d, %Y').upper()
for line in raw.split('\n'):
    line = line.strip().strip('\u2551').strip()
    if re.search(r'(MONDAY|TUESDAY|WEDNESDAY|THURSDAY|FRIDAY|SATURDAY|SUNDAY)', line.upper()):
        if re.search(r'\d{4}', line):
            date_str = line.strip('[]').strip()
            break

# ── Status color ──────────────────────────────────────────────────
status_upper = (status[:100] if status else "").upper()
if 'GREEN' in status_upper:
    status_color = '#34a853'
    status_bg    = '#e6f4ea'
    status_icon  = '\U0001f7e2'
elif 'RED' in status_upper:
    status_color = '#ea4335'
    status_bg    = '#fce8e6'
    status_icon  = '\U0001f534'
else:
    status_color = '#e37400'
    status_bg    = '#fef9e7'
    status_icon  = '\U0001f7e1'

# ── Deadline days ─────────────────────────────────────────────────
dl_match  = re.search(r'(\d+)\s*days? until', raw, re.IGNORECASE)
days_left = dl_match.group(1) if dl_match else "?"

# ── Parse task checkboxes ─────────────────────────────────────────
def parse_tasks(text, marker_words):
    """Extract [ ] checkbox items after a section marker."""
    start = -1
    for mw in marker_words:
        idx = text.upper().find(mw.upper())
        if idx != -1:
            start = text.find('\n', idx)
            if start != -1:
                start += 1
            break
    if start == -1:
        return []
    # Stop at next section marker
    stops = ['CRITICAL', 'TODAY', 'IF TIME', 'TOTAL', '\u23f1', 'PARTS']
    end = len(text)
    for s in stops:
        ei = text.upper().find(s, start)
        if ei != -1 and ei < end and ei > start + 5:
            end = ei
    items = []
    for line in text[start:end].split('\n'):
        line = line.strip()
        if re.match(r'^\[.?\]', line):
            clean = re.sub(r'^\[.?\]\s*', '', line).strip()
            if clean:
                items.append(clean)
    return items

critical_tasks = parse_tasks(tasks, ['CRITICAL'])
today_tasks    = parse_tasks(tasks, ['TODAY'])
iftime_tasks   = parse_tasks(tasks, ['IF TIME', 'IF_TIME'])

total_match = re.search(r'[Tt]otal\s+estimated[:\s]*(~?[\d\.\-]+\s*h[a-z]*)', raw)
total_hrs   = total_match.group(1).strip() if total_match else ""

# ── Fallback: if no checkboxes found, use raw lines ───────────────
def raw_lines(text, max_lines=6):
    if not text:
        return []
    lines = [l.strip() for l in text.split('\n') if l.strip()]
    lines = [l for l in lines if not re.match(r'^[-=\u2501\u2550]+$', l)]
    return lines[:max_lines]

if not critical_tasks and not today_tasks:
    today_tasks = raw_lines(tasks)

# ── HTML builders (string concat only, no f-strings) ─────────────
def task_card(items, bg, border, label, icon):
    if not items:
        return ''
    rows = ''
    for item in items:
        rows += (
            '<div style="background:' + bg + ';border-left:4px solid ' + border + ';'
            'border-radius:5px;padding:11px 14px;margin:5px 0;font-size:14px;'
            'line-height:1.5">' + item + '</div>'
        )
    return (
        '<div style="background:#fff;border-radius:10px;padding:18px 20px;'
        'margin-bottom:14px;box-shadow:0 1px 4px rgba(0,0,0,0.07)">'
        '<div style="font-size:11px;font-weight:700;letter-spacing:1.5px;'
        'text-transform:uppercase;color:' + border + ';margin-bottom:10px">'
        + icon + ' ' + label + '</div>' + rows + '</div>'
    )

def text_card(title, icon, content, border_color):
    if not content:
        return ''
    lines = [l.strip() for l in content.split('\n') if l.strip()]
    lines = [l for l in lines if not re.match(r'^[-=\u2501]+$', l)]
    paras = ''
    for l in lines:
        paras += (
            '<p style="margin:5px 0;font-size:14px;line-height:1.7">'
            + l + '</p>'
        )
    return (
        '<div style="background:#fff;border-radius:10px;padding:18px 20px;'
        'margin-bottom:14px;box-shadow:0 1px 4px rgba(0,0,0,0.07);'
        'border-left:4px solid ' + border_color + '">'
        '<div style="font-size:11px;font-weight:700;letter-spacing:1.5px;'
        'text-transform:uppercase;color:' + border_color + ';margin-bottom:10px">'
        + icon + ' ' + title + '</div>' + paras + '</div>'
    )

def risks_card(risks_text):
    if not risks_text:
        return ''
    # Group lines into risk items — a new item starts with a number like "1." "2." "3."
    # All following lines until the next number are part of the same item
    raw_lines = [l.strip() for l in risks_text.split('\n') if l.strip()]
    raw_lines = [l for l in raw_lines if not re.match(r'^[-=\u2501]+$', l)]

    # Build grouped risk items
    risk_items = []
    current = []
    for line in raw_lines:
        if re.match(r'^\d+[.\)]', line):
            if current:
                risk_items.append(' '.join(current))
            current = [line]
        else:
            current.append(line)
    if current:
        risk_items.append(' '.join(current))

    # If no numbered items found, fall back to treating each line as an item
    if not risk_items:
        risk_items = raw_lines

    rows = ''
    for item in risk_items:
        up = item.upper()
        dot = '#ea4335' if 'HIGH' in up else '#fbbc04' if 'MED' in up else '#34a853'
        # Bold the numbered prefix if present
        formatted = re.sub(r'^(\d+[.\)]\s*)', r'<strong>\1</strong>', item)
        rows += (
            '<div style="display:flex;gap:12px;align-items:flex-start;'
            'padding:12px 0;border-bottom:1px solid #f0f0f0">'
            '<div style="width:9px;height:9px;border-radius:50%;background:' + dot + ';'
            'flex-shrink:0;margin-top:5px"></div>'
            '<span style="font-size:13px;line-height:1.7">' + formatted + '</span>'
            '</div>'
        )
    return (
        '<div style="background:#fff;border-radius:10px;padding:18px 20px;'
        'margin-bottom:14px;box-shadow:0 1px 4px rgba(0,0,0,0.07)">'
        '<div style="font-size:11px;font-weight:700;letter-spacing:1.5px;'
        'text-transform:uppercase;color:#ea4335;margin-bottom:10px">'
        '\u26a0\ufe0f Top Risks</div>' + rows + '</div>'
    )

def next48_card(text):
    if not text:
        return ''
    lines = [l.strip() for l in text.split('\n') if l.strip()]
    lines = [l for l in lines if not re.match(r'^[-=\u2501]+$', l)]

    # Group continuation lines into single action items
    actions = []
    current = []
    for line in lines:
        is_new = (
            line.startswith('\u2192')
            or line.startswith('-')
            or line.startswith('\u2022')
            or re.match(r'^\d+[.)]', line)
        )
        if is_new:
            if current:
                actions.append(' '.join(current))
            current = [line.lstrip('\u2192').lstrip('-').lstrip('\u2022').lstrip('0123456789.)').strip()]
        else:
            current.append(line)
    if current:
        actions.append(' '.join(current))
    if not actions:
        actions = [l.lstrip('\u2192-\u2022').strip() for l in lines if l.strip()]

    rows = ''
    for action in actions:
        if action:
            rows += (
                '<div style="display:flex;gap:10px;align-items:flex-start;'
                'padding:8px 0;border-bottom:1px solid #f0f0f0">'
                '<span style="color:#0077aa;font-weight:700;font-size:16px;'
                'line-height:1.2;flex-shrink:0">\u2192</span>'
                '<span style="font-size:14px;line-height:1.6">' + action + '</span>'
                '</div>'
            )
    return (
        '<div style="background:#fff;border-radius:10px;padding:18px 20px;'
        'margin-bottom:14px;box-shadow:0 1px 4px rgba(0,0,0,0.07);'
        'border-left:4px solid #0077aa">'
        '<div style="font-size:11px;font-weight:700;letter-spacing:1.5px;'
        'text-transform:uppercase;color:#0077aa;margin-bottom:10px">'
        '\u26a1 Next 48 Hours</div>' + rows + '</div>'
    )

def total_bar(hrs):
    if not hrs:
        return ''
    return (
        '<div style="background:#fff;border-radius:10px;padding:14px 20px;'
        'margin-bottom:14px;box-shadow:0 1px 4px rgba(0,0,0,0.07);'
        'display:flex;justify-content:space-between;align-items:center">'
        '<span style="font-size:13px;color:#555;text-transform:uppercase;'
        'letter-spacing:1px">\u23f1 Total Estimated</span>'
        '<span style="font-size:18px;font-weight:700;color:#0077aa">'
        + hrs + '</span></div>'
    )

# ── Assemble body ─────────────────────────────────────────────────
status_first = status.split('\n')[0] if status else 'See full briefing below'
temporal_clean = temporal if temporal else 'Week 3 of 11'

body = (
    text_card('Overall Status', status_icon, status, status_color)
    + task_card(critical_tasks, '#fce8e6', '#ea4335', 'Critical \u2014 Do First', '\U0001f534')
    + task_card(today_tasks,    '#fef9e7', '#fbbc04', 'Today',                    '\U0001f7e1')
    + task_card(iftime_tasks,   '#e6f4ea', '#34a853', 'If Time',                  '\U0001f7e2')
    + total_bar(total_hrs)
    + text_card('Parts & Arrivals This Week', '\U0001f4e6', parts,    '#e37400')
    + text_card("Today's Learning Concept",   '\U0001f9e0', learning, '#6a0dad')
    + risks_card(risks)
    + next48_card(next48)
)

# ── Full HTML ─────────────────────────────────────────────────────
html = (
    '<!DOCTYPE html><html><head>'
    '<meta charset="utf-8">'
    '<meta name="viewport" content="width=device-width,initial-scale=1">'
    '</head><body style="margin:0;padding:0;background:#f0f4f8;'
    'font-family:Arial,sans-serif;color:#222">'
    '<div style="max-width:620px;margin:0 auto;padding:20px">'

    # Header card
    '<div style="background:linear-gradient(135deg,#0d2e4d,#0077aa);'
    'border-radius:12px;padding:26px 28px;margin-bottom:16px">'
    '<div style="font-size:11px;color:#7ec8e3;letter-spacing:2px;'
    'text-transform:uppercase;margin-bottom:6px">'
    'ASV Project \u00b7 Daily Briefing</div>'
    '<h1 style="color:#fff;margin:0 0 14px;font-size:19px;font-weight:700">'
    '\U0001f6a2 ' + date_str + '</h1>'
    '<div style="background:rgba(255,255,255,0.1);border-radius:6px;'
    'padding:10px 14px;font-size:13px;color:#cce8f4;margin-bottom:10px">'
    + temporal_clean +
    '</div>'
    '<div style="background:' + status_bg + ';border-radius:6px;'
    'padding:10px 14px;font-size:13px;color:#333">'
    + status_icon + ' ' + status_first +
    '</div></div>'

    # Deadline bar
    '<div style="background:#0d2e4d;border-radius:8px;padding:12px 20px;'
    'margin-bottom:16px;display:flex;justify-content:space-between;align-items:center">'
    '<span style="color:#7ec8e3;font-size:12px;letter-spacing:1px;'
    'text-transform:uppercase">Deadline</span>'
    '<span style="color:#fff;font-size:15px;font-weight:700">'
    '\u23f3 ' + days_left + ' days until August 10</span></div>'

    + body +

    '<div style="text-align:center;font-size:11px;color:#aaa;padding:10px 0">'
    'ASV Project \u00b7 August 10 2026 Deadline \u00b7 ASV Briefing Bot'
    '</div></div></body></html>'
)

# ── Send ──────────────────────────────────────────────────────────
# Credentials must be set as environment variables — never hardcode here.
# Copy .env.example to .env and fill in values before running.
SENDER_EMAIL    = os.environ["ASV_SENDER_EMAIL"]
SENDER_PASSWORD = os.environ["ASV_SENDER_PASSWORD"]
RECEIVER_EMAIL  = os.environ["ASV_RECEIVER_EMAIL"]

today_label = date.today().strftime('%A, %b %d')
msg = MIMEMultipart('alternative')
msg['Subject'] = "\U0001f6a2 ASV Briefing \u2014 " + today_label
msg['From']    = "ASV Briefing Bot <" + SENDER_EMAIL + ">"
msg['To']      = RECEIVER_EMAIL

msg.attach(MIMEText(raw,  'plain'))
msg.attach(MIMEText(html, 'html'))

try:
    with smtplib.SMTP_SSL('smtp.gmail.com', 465) as server:
        server.login(SENDER_EMAIL, SENDER_PASSWORD)
        server.send_message(msg)
    print("Briefing sent to " + RECEIVER_EMAIL)
except Exception as e:
    print("Email failed: " + str(e))