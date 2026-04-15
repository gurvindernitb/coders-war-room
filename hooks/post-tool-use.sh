#!/bin/bash
# hooks/post-tool-use.sh — PostToolUse hook
# Fires after every Claude Code tool call. Silent, background, zero agent impact.
set -euo pipefail

AGENT_NAME="${WARROOM_AGENT_NAME:-unknown}"
WARROOM_URL="${WARROOM_URL:-http://localhost:5680}"

# Read hook input JSON from stdin
INPUT=$(cat)

# Extract tool name safely via env var passthrough
TOOL_NAME=$(HOOK_INPUT="$INPUT" python3 -c "
import sys, json, os
try:
    d = json.loads(os.environ['HOOK_INPUT'])
    print(d.get('tool_name', ''))
except: print('')
" 2>/dev/null || echo "")

[ -z "$TOOL_NAME" ] && exit 0

# Skip noisy/meta tools that don't represent meaningful activity
case "$TOOL_NAME" in
  ToolSearch|TaskList|TaskGet|TaskUpdate|TaskCreate) exit 0 ;;
esac

# Build human-readable summary via env var (safe interpolation)
SUMMARY=$(HOOK_INPUT="$INPUT" TNAME="$TOOL_NAME" python3 -c "
import json, os
try:
    d = json.loads(os.environ['HOOK_INPUT'])
    inp = d.get('tool_input', {})
    t = os.environ.get('TNAME', '')
    if t == 'Read':
        s = 'Read → ' + inp.get('file_path', '?').split('/')[-1]
    elif t == 'Edit':
        s = 'Edit → ' + inp.get('file_path', '?').split('/')[-1]
    elif t == 'Write':
        s = 'Write → ' + inp.get('file_path', '?').split('/')[-1]
    elif t == 'Bash':
        cmd = inp.get('command', '?')
        s = 'Bash → ' + cmd[:80]
    elif t == 'Grep':
        s = 'Grep → ' + inp.get('pattern', '?')[:60]
    elif t == 'Glob':
        s = 'Glob → ' + inp.get('pattern', '?')[:60]
    elif t == 'Agent':
        s = 'Agent → ' + inp.get('description', '?')[:60]
    elif t == 'Skill':
        s = 'Skill → ' + inp.get('skill', '?')
    else:
        s = t
    print(s[:200])
except:
    print(os.environ.get('TNAME', 'tool'))
" 2>/dev/null || echo "$TOOL_NAME")

# POST to War Room — fire and forget (background curl, never block agent)
PAYLOAD=$(AGENT="$AGENT_NAME" SUMM="$SUMMARY" TNAME="$TOOL_NAME" python3 -c "
import json, os
print(json.dumps({
    'agent': os.environ['AGENT'],
    'event_type': 'tool_use',
    'tool': os.environ['TNAME'],
    'exit_code': 0,
    'summary': os.environ['SUMM'][:200]
}))
" 2>/dev/null || echo '{}')

curl -sf -X POST "${WARROOM_URL}/api/hooks/event" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD" \
  2>/dev/null &

exit 0
