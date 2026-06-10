@echo off
cd /d C:\Users\mirth\OneDrive\Desktop\asv-project
echo Running daily briefing agent...
claude --agent daily-briefing --dangerously-skip-permissions --print "Generate today's daily briefing. Read CLAUDE.md and docs/progress.md. Save output to docs/daily_briefing.txt." > docs\agent_log.txt 2>&1
echo Sending email...
python send_briefing.py
echo Done.