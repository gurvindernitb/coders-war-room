# Live Agent Activity Hooks — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace passive 10-second tmux polling with push-based Claude Code hooks so agent cards display real-time tool activity.

**Architecture:** A PostToolUse hook script fires after every Claude Code tool call, POSTing tool name and summary to the War Room server's existing `/api/hooks/event` endpoint. The server stores a per-agent last-tool timestamp. The existing `agent_status_loop` merges hook-reported activity (if < 30s old) into the WebSocket broadcast. The UI's WebSocket handler distinguishes `tool_use` events from gate events, updating the card's live panel instantly.

**Tech Stack:** Bash (hook script), Python/FastAPI (server), Vanilla JS (UI)

---

### Task 1: Create the PostToolUse hook script

**Files:**
- Create: `hooks/post-tool-use.sh`

- [ ] **Step 1: Create the hook script**

```bash
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
```

- [ ] **Step 2: Make it executable**

Run: `chmod +x hooks/post-tool-use.sh`

- [ ] **Step 3: Verify script runs without error on mock input**

Run:
```bash
echo '{"tool_name":"Read","tool_input":{"file_path":"/Users/test/server.py"}}' | WARROOM_AGENT_NAME=test WARROOM_URL=http://localhost:5680 bash hooks/post-tool-use.sh && echo "OK"
```
Expected: `OK` (curl may fail if no agent "test" exists, but the script itself should exit 0)

- [ ] **Step 4: Commit**

```bash
git add hooks/post-tool-use.sh
git commit -m "feat: add PostToolUse hook for live activity reporting"
```

---

### Task 2: Add activity field to server AgentStatus model + 30s TTL

**Files:**
- Modify: `server.py:96-124` (constants), `server.py:882-888` (AgentStatus model), `server.py:1116-1151` (set_agent_status), `server.py:638-652` (agent_status_loop)

- [ ] **Step 1: Add activity TTL constant and state dict**

In `server.py`, after line 123 (`STALE_EXEMPT_TOOLS`), add:

```python
ACTIVITY_TTL_SECONDS = 30  # Tool activity clears after 30s of silence
agent_last_tool_activity: dict[str, dict] = {}  # {agent: {"summary": str, "tool": str, "at": float}}
```

- [ ] **Step 2: Add activity field to AgentStatus model**

In `server.py`, change the `AgentStatus` class (line 882) from:

```python
class AgentStatus(BaseModel):
    task: Optional[str] = None
    progress: Optional[int] = None
    eta: Optional[str] = None
    blocked_by: Optional[str] = None
    blocked_reason: Optional[str] = None
    clear: bool = False
```

to:

```python
class AgentStatus(BaseModel):
    task: Optional[str] = None
    progress: Optional[int] = None
    eta: Optional[str] = None
    blocked_by: Optional[str] = None
    blocked_reason: Optional[str] = None
    activity: Optional[str] = None
    clear: bool = False
```

- [ ] **Step 3: Store activity in set_agent_status handler**

In `server.py` `set_agent_status()` function (line 1116), after the `blocked_reason` handling block (after line 1138), add:

```python
    if body.activity is not None:
        current["activity"] = body.activity
```

- [ ] **Step 4: Record tool_use events in receive_hook_event**

In `server.py` `receive_hook_event()` function (line 1759), after the `await db.commit()` line (line 1773), add:

```python
    # Track latest tool activity for live card display
    if event.event_type == "tool_use" and event.agent:
        agent_last_tool_activity[event.agent] = {
            "summary": summary,
            "tool": event.tool,
            "at": time.time(),
        }
```

- [ ] **Step 5: Merge hook activity into agent_status_loop broadcast**

In `server.py` `agent_status_loop()`, change line 640 from:

```python
                "activity": activity.get("activity"),
```

to:

```python
                "activity": _get_live_activity(name, activity),
```

And add this helper function before `agent_status_loop()` (around line 598):

```python
def _get_live_activity(agent_name: str, tmux_activity: dict) -> Optional[str]:
    """Return the most recent activity: hook-reported (if < 30s old) > tmux-detected."""
    hook = agent_last_tool_activity.get(agent_name)
    if hook and (time.time() - hook["at"]) < ACTIVITY_TTL_SECONDS:
        return hook["summary"]
    # Expired hook activity — clean up
    if hook and (time.time() - hook["at"]) >= ACTIVITY_TTL_SECONDS:
        agent_last_tool_activity.pop(agent_name, None)
    return tmux_activity.get("activity")
```

- [ ] **Step 6: Commit**

```bash
git add server.py
git commit -m "feat: server accepts tool_use activity with 30s TTL"
```

---

### Task 3: Wire PostToolUse hook into hook-registry and settings generator

**Files:**
- Modify: `registries/hook-registry.yaml`
- No changes needed to `settings_generator.py` — it already resolves hook templates

- [ ] **Step 1: Add activity-reporting hook template to hook-registry.yaml**

Add at the end of the `templates:` section in `registries/hook-registry.yaml`:

```yaml
  activity-reporting:
    description: "Reports tool activity to War Room for live card display"
    hooks:
      PostToolUse:
        - type: command
          command: "hooks/post-tool-use.sh"
          async: true
          timeout: 5
```

- [ ] **Step 2: Add the template to every role in role-registry.yaml**

In `registries/role-registry.yaml`, add `- template: activity-reporting` to the `hooks:` list of every role. For each role (supervisor, scout, engineer, qa, git-agent, chronicler), add it as the last hook entry. Example for supervisor:

```yaml
    hooks:
      - template: base-hooks
      - template: no-code-hooks
      - template: activity-reporting
```

For engineer (which has more hooks):

```yaml
    hooks:
      - template: base-hooks
      - template: engineer-stop-gate
      - template: post-edit-lint
      - template: activity-reporting
```

Do this for ALL six roles.

- [ ] **Step 3: Verify settings generation works**

Run:
```bash
cd ~/coders-war-room && python3 settings_generator.py supervisor
```
Expected: Settings generated successfully. Check the output file contains PostToolUse hook entry with `post-tool-use.sh`.

Run:
```bash
cat ~/contextualise/.claude/settings.local.json | python3 -m json.tool | grep -A5 PostToolUse
```
Expected: Shows the post-tool-use.sh hook command.

- [ ] **Step 4: Commit**

```bash
git add registries/hook-registry.yaml registries/role-registry.yaml
git commit -m "feat: wire activity-reporting hook into all agent roles"
```

---

### Task 4: Update UI to handle tool_use events separately from gate events

**Files:**
- Modify: `static/index.html` (JS only, ~lines 1701-1704)

- [ ] **Step 1: Update the WebSocket hook_event handler**

In `static/index.html`, find the `hook_event` handler (line 1701):

```javascript
    else if (d.type === 'hook_event') {
      if (!agentHookEvents[d.agent]) agentHookEvents[d.agent] = {};
      agentHookEvents[d.agent][d.tool] = { exit_code: d.exit_code, summary: d.summary, timestamp: d.timestamp };
      updateAgentGateStatus(d.agent);
    }
```

Replace with:

```javascript
    else if (d.type === 'hook_event') {
      if (d.event_type === 'tool_use') {
        // Live activity — update the agent's activity in real time
        if (agentData[d.agent]) {
          agentData[d.agent].activity = d.summary;
          agentData[d.agent].presence = agentData[d.agent].presence === 'offline' ? 'offline' : 'busy';
          agentData[d.agent]._lastToolAt = d.timestamp || new Date().toISOString();
        }
        renderAgents();
      } else {
        // Gate/hook events — update gate dots
        if (!agentHookEvents[d.agent]) agentHookEvents[d.agent] = {};
        agentHookEvents[d.agent][d.tool] = { exit_code: d.exit_code, summary: d.summary, timestamp: d.timestamp };
        updateAgentGateStatus(d.agent);
      }
    }
```

- [ ] **Step 2: Add relative timestamp to the live activity panel**

In the `renderAgents()` function, find the line that builds `liveHtml` for the activity block (around line 2003):

```javascript
    if (activity || task) {
      const actText = activity || task;
      const actClass = presence === 'typing' ? ' tp' : '';
      liveHtml += `<div class="live-activity${actClass}"><div class="live-activity-label">${presence === 'typing' ? 'Thinking' : 'Activity'}</div>${esc(actText)}</div>`;
    }
```

Replace with:

```javascript
    if (activity || task) {
      const actText = activity || task;
      const actClass = presence === 'typing' ? ' tp' : '';
      const lastToolAt = d._lastToolAt;
      let agoText = '';
      if (lastToolAt) {
        const secAgo = Math.round((Date.now() - new Date(lastToolAt).getTime()) / 1000);
        if (secAgo < 5) agoText = ' · just now';
        else if (secAgo < 60) agoText = ` · ${secAgo}s ago`;
        else if (secAgo < 3600) agoText = ` · ${Math.round(secAgo/60)}m ago`;
      }
      liveHtml += `<div class="live-activity${actClass}"><div class="live-activity-label">${presence === 'typing' ? 'Thinking' : 'Activity'}${agoText}</div>${esc(actText)}</div>`;
    }
```

- [ ] **Step 3: Commit**

```bash
git add static/index.html
git commit -m "feat: UI handles tool_use events for real-time card activity"
```

---

### Task 5: End-to-end verification

**Files:** None (testing only)

- [ ] **Step 1: Restart the server to pick up server.py changes**

Run:
```bash
cd ~/coders-war-room && kill $(lsof -ti:5680) 2>/dev/null; sleep 1; nohup python3 server.py > /tmp/warroom-server.log 2>&1 &
sleep 2
curl -s http://localhost:5680/api/server/health | python3 -m json.tool
```
Expected: Server responds with health JSON.

- [ ] **Step 2: Simulate a tool_use event**

Run:
```bash
curl -s -X POST http://localhost:5680/api/hooks/event \
  -H "Content-Type: application/json" \
  -d '{"agent":"supervisor","event_type":"tool_use","tool":"Read","exit_code":0,"summary":"Read → server.py"}' | python3 -m json.tool
```
Expected: `{"status": "stored"}` or similar success response.

- [ ] **Step 3: Verify the activity appears in agent status**

Run:
```bash
curl -s http://localhost:5680/api/agents/supervisor/status | python3 -m json.tool | grep activity
```
Expected: `"activity": "Read → server.py"`

- [ ] **Step 4: Verify UI receives the update**

Open `http://localhost:5680` in browser. The supervisor card's live panel should show:
- Activity block with "Read → server.py"
- "Activity · just now" label

- [ ] **Step 5: Verify 30s TTL clears activity**

Wait 35 seconds. Refresh the page. The activity should be cleared (null).

- [ ] **Step 6: Test the actual hook with a live agent**

If a tmux agent session is running:
```bash
# Manually trigger the hook as if Claude Code fired it
echo '{"tool_name":"Bash","tool_input":{"command":"pytest tests/ -q"}}' | \
  WARROOM_AGENT_NAME=supervisor WARROOM_URL=http://localhost:5680 \
  bash ~/coders-war-room/hooks/post-tool-use.sh
```
Check the UI — supervisor card should show "Bash → pytest tests/ -q" in the live panel.

- [ ] **Step 7: Final commit — all changes verified**

```bash
git add -A
git status
# If any uncommitted changes remain, commit them
git commit -m "feat: live activity hooks — end-to-end verified"
```
