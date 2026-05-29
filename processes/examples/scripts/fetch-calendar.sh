#!/usr/bin/env bash
# fetch-calendar.sh — demo stub. Echoes plausible calendar events JSON.
# No real API calls are made. Safe to run in any environment.
cat <<'EOF'
{"success": true, "events": [{"time": "10:00", "title": "1:1 with Pat"}, {"time": "14:30", "title": "Design review"}]}
EOF
