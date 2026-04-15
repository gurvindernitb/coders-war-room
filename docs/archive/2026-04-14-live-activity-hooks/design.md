# Live Agent Activity Hooks — Design Spec

## Problem

The War Room UI agent cards show no live activity even though agents are actively working in CLI sessions. The current system polls tmux pane content every 10 seconds looking for braille spinner characters, but Claude Code spinners are ephemeral (< 1 second for most tools). The polling window misses them ~95% of the time.

**Result:** Cards show "idle" with null activity while agents are actively reading files, running tests, and writing code.

## Root Cause

**Passive terminal scraping can't capture ephemeral state.** The `_has_busy_indicators()` function in `server.py:390` checks the last 5 lines of tmux output for spinner chars. By the time the 10-second poll runs, the spinner is gone and replaced by completed output markers (`⏺`).

## Solution: Push-Based Hooks

Claude Code supports hook scripts that fire automatically on system events. These run as silent background subprocesses — **invisible to the agent, zero context consumption, no cognitive load.** The same mechanism `hooks/session-start.sh` already uses.

We add two hooks:

### Hook 1: `hooks/post-tool-use.sh` (PostToolUse event)

**Fires:** After every Claude Code tool call completes.
**Receives:** Tool name, input/output (via stdin JSON).
**Does:** POSTs to `POST /api/hooks/event` with tool name, exit code, and a brief summary.

```bash
#!/bin/bash
# hooks/post-tool-use.sh — Silent background hook, invisible to agent
set -euo pipefail

AGENT_NAME="${WARROOM_AGENT_NAME:-unknown}"
WARROOM_URL="${WARROOM_URL:-http://localhost:5680}"

# Read the hook input from stdin (Claude Code passes JSON)
INPUT=$(cat)

TOOL_NAME=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_name',''))" 2>/dev/null || echo "")
TOOL_INPUT=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); inp=d.get('tool_input',{}); print(json.dumps(inp)[:200])" 2>/dev/null || echo "{}")

# Skip noisy/frequent tools
case "$TOOL_NAME" in
  ToolSearch|TaskList|TaskGet) exit 0 ;;
esac

# Compose a brief summary
SUMMARY="${TOOL_NAME}"
case "$TOOL_NAME" in
  Read) SUMMARY="Read → $(echo "$TOOL_INPUT" | python3 -c "import sys,json;print(json.load(sys.stdin).get('file_path','').split('/')[-1])" 2>/dev/null || echo "file")" ;;
  Edit) SUMMARY="Edit → $(echo "$TOOL_INPUT" | python3 -c "import sys,json;print(json.load(sys.stdin).get('file_path','').split('/')[-1])" 2>/dev/null || echo "file")" ;;
  Write) SUMMARY="Write → $(echo "$TOOL_INPUT" | python3 -c "import sys,json;print(json.load(sys.stdin).get('file_path','').split('/')[-1])" 2>/dev/null || echo "file")" ;;
  Bash) SUMMARY="Bash → $(echo "$TOOL_INPUT" | python3 -c "import sys,json;cmd=json.load(sys.stdin).get('command','');print(cmd[:80])" 2>/dev/null || echo "command")" ;;
  Grep) SUMMARY="Grep → $(echo "$TOOL_INPUT" | python3 -c "import sys,json;print(json.load(sys.stdin).get('pattern','')[:60])" 2>/dev/null || echo "pattern")" ;;
  Glob) SUMMARY="Glob → $(echo "$TOOL_INPUT" | python3 -c "import sys,json;print(json.load(sys.stdin).get('pattern','')[:60])" 2>/dev/null || echo "pattern")" ;;
  Agent) SUMMARY="Agent → $(echo "$TOOL_INPUT" | python3 -c "import sys,json;print(json.load(sys.stdin).get('description','')[:60])" 2>/dev/null || echo "subagent")" ;;
  Skill) SUMMARY="Skill → $(echo "$TOOL_INPUT" | python3 -c "import sys,json;print(json.load(sys.stdin).get('skill',''))" 2>/dev/null || echo "skill")" ;;
esac

# POST to War Room — fire and forget, never block the agent
curl -sf -X POST "${WARROOM_URL}/api/hooks/event" \
  -H "Content-Type: application/json" \
  -d "{\"agent\": \"${AGENT_NAME}\", \"event_type\": \"tool_use\", \"tool\": \"${TOOL_NAME}\", \"exit_code\": 0, \"summary\": $(python3 -c "import json;print(json.dumps('${SUMMARY//\'/\\\'}'[:200]))" 2>/dev/null || echo "\"${TOOL_NAME}\"")}" \
  2>/dev/null &

exit 0
```

**Key properties:**
- `curl` runs with `&` (background) — hook returns instantly, never delays Claude Code
- Skips noisy tools (ToolSearch, TaskList) to avoid flooding
- Summary is human-readable: "Read → server.py", "Bash → pytest tests/ -q"
- Max 200 chars per summary
- All errors silently ignored (`2>/dev/null`, `|| true`)

### Hook 2: `hooks/notification.sh` (Notification event)

**Fires:** When Claude Code's status line updates (the spinner text that shows current action).
**Receives:** The notification message via stdin JSON.
**Does:** POSTs to `POST /api/agents/{name}/status` to set the activity field.

```bash
#!/bin/bash
# hooks/notification.sh — Captures Claude Code status line updates
set -euo pipefail

AGENT_NAME="${WARROOM_AGENT_NAME:-unknown}"
WARROOM_URL="${WARROOM_URL:-http://localhost:5680}"

INPUT=$(cat)
MESSAGE=$(echo "$INPUT" | python3 -c "import sys,json;d=json.load(sys.stdin);print(d.get('message','')[:200])" 2>/dev/null || echo "")

[ -z "$MESSAGE" ] && exit 0

# POST activity update — fire and forget
curl -sf -X POST "${WARROOM_URL}/api/agents/${AGENT_NAME}/status" \
  -H "Content-Type: application/json" \
  -d "{\"activity\": $(python3 -c "import json;print(json.dumps('$MESSAGE'[:200]))" 2>/dev/null || echo "\"working\"")}" \
  2>/dev/null &

exit 0
```

**Note:** The Notification hook type may not be available in current Claude Code versions. If not, PostToolUse alone provides sufficient coverage. The activity will update on every tool call, which happens frequently during active work (every few seconds).

### Hook Wiring: `settings_generator.py`

The settings generator already produces per-agent `settings.json` files. Add these hooks to every agent's configuration:

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "type": "command",
        "command": "WARROOM_AGENT_NAME=$AGENT_NAME WARROOM_URL=http://localhost:5680 bash ~/coders-war-room/hooks/post-tool-use.sh"
      }
    ]
  }
}
```

Environment variables `WARROOM_AGENT_NAME` and `WARROOM_URL` are already set by the agent onboarding process.

## Server Changes

### New field: `activity` on `/api/agents/{name}/status`

The `AgentStatus` Pydantic model in server.py needs an `activity: Optional[str]` field. When set via POST, it's stored in `agent_manual_status` and surfaced in the `agent_status` WebSocket broadcast.

This is a 3-line addition to server.py:
1. Add `activity: Optional[str] = None` to `AgentStatus` model
2. In `set_agent_status()`, store `body.activity` in the manual status dict
3. In `agent_status_loop()`, prefer manual activity over tmux-detected activity (manual is more recent/accurate)

### Merge logic: manual activity > tmux activity

In `agent_status_loop()` (server.py:638), change:
```python
"activity": activity.get("activity"),
```
to:
```python
"activity": manual.get("activity") or activity.get("activity"),
```

This means: if a hook recently posted activity, show that. Otherwise fall back to tmux detection. The manual status TTL (30 minutes) auto-clears stale entries.

## UI Changes

### The card live panel already handles this

The `renderAgents()` function already reads `d.activity` and displays it in the `.live-activity` block. **No UI JS changes needed.** When the server starts sending real activity data via the hook pipeline, the cards will light up automatically.

### Hook events → gate dots

The PostToolUse hook fires `tool_use` events to `/api/hooks/event`. The existing `updateAgentGateStatus()` function reads from `agentHookEvents` and renders gate dots. Currently it only shows gate tool results (pytest, flake8, etc.) but the new `tool_use` events will also appear.

**Filter needed:** The UI should distinguish between gate events (pytest/flake8/mypy) and general tool_use events. Gate dots should only show gate tools. The live-activity panel shows everything else.

This is a small JS filter in the WebSocket `hook_event` handler — only store events where `event_type === 'hook_event'` (from gate scripts) in `agentHookEvents`. Events where `event_type === 'tool_use'` update the activity display instead.

## Refinements (Post-Review)

### 1. Activity TTL: 30 seconds (not 30 minutes)

Tool activity uses a separate TTL from manual status (task/progress/blocked). The server's `agent_status_loop` checks: if the last `tool_use` event for an agent is > 30 seconds old, clear the activity field. During active work, tools fire every 2-5 seconds, so 30s of silence = genuinely idle.

**Implementation:** Add `agent_last_tool_time: dict[str, float]` to server.py. Updated by the `/api/hooks/event` handler when `event_type == "tool_use"`. Checked in `agent_status_loop` — if `time.time() - agent_last_tool_time[name] > 30`, set activity to None.

### 2. Safe string interpolation

All Bash-to-Python interpolation uses environment variables, never string injection:
```bash
# Instead of: python3 -c "print('${SUMMARY}')"
# Use:
SUMMARY="$SUMMARY" python3 -c "import os,json; print(json.dumps(os.environ.get('SUMMARY','')[:200]))"
```

### 3. Relative timestamp on activity display

The UI shows when the last tool fired: "Read → server.py · 5s ago". Updated by comparing the event timestamp against `Date.now()`. This makes it obvious whether the agent is actively executing or in a thinking pause.

**Implementation:** Store `tool_use` event timestamps in `agentHookEvents`. The `agent_status_loop` broadcast already runs every 10s — on each broadcast, the UI's `renderAgents()` recalculates relative times.

### 4. DOM overwrite, never append

Each `tool_use` WebSocket event fully replaces the `.live-activity` content in the card. No accumulation, no memory leak. The gate dots (`.ac-gates`) remain separate and accumulate as before (they represent persistent gate results, not ephemeral activity).

## Files to Modify

| File | Change | Scope |
|------|--------|-------|
| `hooks/post-tool-use.sh` | **CREATE** | New hook script — push tool activity to server |
| `hooks/notification.sh` | **CREATE** | New hook script (if Notification hook supported) |
| `server.py` | **~15 lines** | Add `activity` to AgentStatus, 30s TTL logic, merge in status loop |
| `settings_generator.py` | **~5 lines** | Add PostToolUse hook to generated settings |
| `static/index.html` | **~20 lines JS** | Filter tool_use vs gate events, relative timestamps, DOM overwrite |

## What Agents Experience

**Nothing.** Zero cognitive load. The hooks are:
- Configured in `settings.json` (not in prompts or instructions)
- Shell scripts that run as background subprocesses
- Invisible in Claude Code's context window
- Fire-and-forget (`curl &`) — never delay tool execution
- All errors silently swallowed

This is identical to how `session-start.sh` already works for every agent session today.

## Testing

1. Start a test agent: `~/coders-war-room/join.sh test-agent engineer ~/contextualise`
2. Have the agent run a few tools (Read, Bash, Grep)
3. Watch `http://localhost:5680` — the card should update within seconds showing "Read → file.py", "Bash → pytest...", etc.
4. Gate dots should still work for pytest/flake8 results
5. When the agent goes idle, activity should show the last tool used with "· Xs ago" timestamp, then clear after 30 seconds

## Rollback

Remove the hooks from settings.json. No other changes affect existing behavior — the tmux polling continues to work as before as a fallback.
