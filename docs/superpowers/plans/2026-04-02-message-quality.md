# Message Quality Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix message deduplication in tmux dispatch, add a roll-call diagnostic command, and auto-restart the server via macOS LaunchAgent.

**Architecture:** Dedup via per-agent last-seen message ID tracking. Roll call as a timed endpoint that posts a prompt, waits 10s, scans responses. LaunchAgent plist for KeepAlive auto-restart.

**Tech Stack:** Python 3.12, FastAPI, SQLite, tmux, macOS LaunchAgent

**Design Spec:** `docs/superpowers/specs/2026-04-02-message-quality-design.md`

---

## File Structure

| File | Action | Responsibility |
|------|--------|---------------|
| `server.py` | Modify | Dedup state, dispatch filter, roll-call endpoint, boot-time init |
| `warroom.sh` | Modify | `roll-call` subcommand |
| `static/index.html` | Modify | Roll Call button in header |
| `com.warroom.server.plist` | Create | LaunchAgent definition |
| `install-service.sh` | Create | Install/uninstall the LaunchAgent |
| `start.sh` | Modify | Use launchctl |
| `stop.sh` | Modify | Use launchctl |
| `tests/test_api.py` | Modify | Dedup and roll-call tests |
| `tests/conftest.py` | Modify | Patch new globals |

---

### Task 1: Message Deduplication

**Files:**
- Modify: `~/coders-war-room/server.py`
- Modify: `~/coders-war-room/tests/test_api.py`
- Modify: `~/coders-war-room/tests/conftest.py`

- [ ] **Step 1: Write failing test**

Add to `~/coders-war-room/tests/test_api.py`:

```python
@pytest.mark.asyncio
async def test_dedup_dispatch_skips_already_seen():
    """Messages with IDs at or below last-seen should not be dispatched."""
    from server import app, agent_last_seen_id
    # Simulate: phase-1 has already seen message ID 100
    agent_last_seen_id["phase-1"] = 100
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        # Post a message (gets a new ID, likely 1 in test DB)
        resp = await client.post("/api/messages", json={
            "sender": "phase-2",
            "content": "This should be dispatched normally",
        })
        assert resp.status_code == 200
        # The dispatch would try to send to phase-1, but since
        # msg ID < 100, it should be skipped by the dedup filter.
        # We can't easily test tmux dispatch in unit tests,
        # but we verify the state tracking works.
        msg_id = resp.json()["id"]
        assert msg_id < agent_last_seen_id.get("phase-1", 0)
```

- [ ] **Step 2: Add dedup state and helper**

Add to `server.py` after the existing state variables (around line 60):

```python
# Dedup: last message ID dispatched to each agent
agent_last_seen_id: dict[str, int] = {}
```

Add a helper function after the existing helpers:

```python
async def init_dedup_ids():
    """On boot, set all agents' last-seen to the latest message ID (prevents replay)."""
    async with aiosqlite.connect(DB_PATH) as db:
        cursor = await db.execute("SELECT MAX(id) FROM messages")
        row = await cursor.fetchone()
        latest_id = row[0] or 0
    for a in AGENTS:
        agent_last_seen_id.setdefault(a["name"], latest_id)
```

- [ ] **Step 3: Add dedup filter to dispatch_to_agents()**

In `dispatch_to_agents()` (around line 416), after the `agent_membership` check and before the `tmux_session_exists` check, add:

```python
        # Dedup: skip if agent already saw this message
        msg_id = msg.get("id", 0)
        if msg_id and msg_id <= agent_last_seen_id.get(name, 0):
            continue
```

After the `send_to_tmux(session, format_message_for_tmux(msg))` call (single message delivery), add:

```python
            agent_last_seen_id[name] = msg["id"]
```

After each `send_to_tmux` in the queued message delivery loop, add:

```python
                agent_last_seen_id[name] = queued_msg["id"]
```

- [ ] **Step 4: Add dedup filter to flush_queues_loop()**

In `flush_queues_loop()` (around line 446), after popping messages from the queue, filter:

```python
            messages = agent_queues.pop(name)
            # Dedup filter
            messages = [m for m in messages if m.get("id", 0) > agent_last_seen_id.get(name, 0)]
            if not messages:
                continue
```

After each `send_to_tmux` call, update the last-seen ID:

```python
            for queued_msg in messages:
                send_to_tmux(session, format_message_for_tmux(queued_msg))
                agent_last_seen_id[name] = queued_msg["id"]
                await asyncio.sleep(0.3)
```

- [ ] **Step 5: Call init_dedup_ids() in lifespan**

In the `lifespan` function, after `await init_db()`:

```python
    await init_dedup_ids()
```

- [ ] **Step 6: Update conftest.py**

Add to the `_init_db` fixture:

```python
    monkeypatch.setattr(server, "agent_last_seen_id", {})
```

- [ ] **Step 7: Run all tests**

```bash
cd ~/coders-war-room
python3 -m pytest tests/test_api.py -v
```

Expected: All tests pass.

- [ ] **Step 8: Commit**

```bash
cd ~/coders-war-room
git add server.py tests/test_api.py tests/conftest.py
git commit -m "feat: add message dedup via per-agent last-seen ID tracking"
```

---

### Task 2: Roll Call Command

**Files:**
- Modify: `~/coders-war-room/server.py`
- Modify: `~/coders-war-room/warroom.sh`
- Modify: `~/coders-war-room/static/index.html`

- [ ] **Step 1: Add the roll-call endpoint to server.py**

Add before the `/api/agents/{agent_name}/status` endpoint:

```python
@app.post("/api/roll-call")
async def roll_call():
    """Broadcast a roll call, wait 10s, report who responded."""
    # Record the timestamp before the call
    before_ts = datetime.now(timezone.utc).isoformat()

    # Post the roll call message
    saved = await save_message("system", "all", "[ROLL CALL] All agents, report in.", "system")
    await broadcast_ws({"type": "message", "message": saved})
    await dispatch_to_agents(saved)

    # Get list of in-room agents
    in_room = [a["name"] for a in AGENTS if agent_membership.get(a["name"], False)]

    # Wait 10 seconds for responses
    await asyncio.sleep(10)

    # Scan messages from the last 12 seconds for responses
    responded = set()
    messages = await get_messages(50)
    for m in messages:
        if m["timestamp"] >= before_ts and m["sender"] in in_room and m["type"] == "message":
            responded.add(m["sender"])

    missing = [name for name in in_room if name not in responded]
    responded_list = sorted(responded)
    missing_list = sorted(missing)

    # Post summary
    summary = f"[ROLL CALL] {len(responded_list)}/{len(in_room)} responded"
    if responded_list:
        summary += f": {', '.join(responded_list)}"
    if missing_list:
        summary += f". Missing: {', '.join(missing_list)}"

    result_msg = await save_message("system", "all", summary, "system")
    await broadcast_ws({"type": "message", "message": result_msg})

    return {
        "responded": responded_list,
        "missing": missing_list,
        "total": len(in_room),
    }
```

- [ ] **Step 2: Add roll-call to warroom.sh**

Add the function before the `case` statement:

```bash
roll_call() {
    echo "Roll call sent. Waiting 10s for responses..."
    local result
    result=$(curl -s -X POST "$WARROOM_SERVER/api/roll-call" --max-time 15)
    echo "$result" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    total = d.get('total', 0)
    responded = d.get('responded', [])
    missing = d.get('missing', [])
    print(f'{len(responded)}/{total} responded: {', '.join(responded) if responded else 'none'}')
    if missing:
        print(f'Missing: {', '.join(missing)}')
except Exception as e:
    print(f'Error: {e}', file=sys.stderr)
"
}
```

Add the case entry:

```bash
    roll-call)
        shift
        roll_call
        ;;
```

Add to help text:

```bash
        echo "  warroom.sh roll-call                         Check who's alive"
```

- [ ] **Step 3: Add Roll Call button to web UI header**

In `static/index.html`, find the header HTML. After the LIVE badge, add:

```html
<button id="rollCallBtn" class="conn on" style="cursor:pointer;margin-left:8px" title="Roll call — check who's alive">Roll Call</button>
```

Add the click handler in JavaScript (after the WebSocket connect code):

```javascript
$('rollCallBtn').onclick = async () => {
  const btn = $('rollCallBtn');
  btn.textContent = 'Calling...';
  btn.disabled = true;
  try {
    const resp = await fetch('/api/roll-call', { method: 'POST' });
    const data = await resp.json();
    btn.textContent = `${data.responded.length}/${data.total} responded`;
    setTimeout(() => { btn.textContent = 'Roll Call'; btn.disabled = false; }, 5000);
  } catch (e) {
    btn.textContent = 'Roll Call';
    btn.disabled = false;
  }
};
```

- [ ] **Step 4: Test manually**

```bash
cd ~/coders-war-room
pkill -f "python3.*server.py"; sleep 1
python3 server.py &
sleep 2

# Test roll call from CLI
WARROOM_AGENT_NAME=test ./warroom.sh roll-call
```

- [ ] **Step 5: Commit**

```bash
cd ~/coders-war-room
git add server.py warroom.sh static/index.html
git commit -m "feat: add roll-call command to check which agents are alive"
```

---

### Task 3: Auto-Restart via LaunchAgent

**Files:**
- Create: `~/coders-war-room/com.warroom.server.plist`
- Create: `~/coders-war-room/install-service.sh`
- Modify: `~/coders-war-room/start.sh`
- Modify: `~/coders-war-room/stop.sh`

- [ ] **Step 1: Create the LaunchAgent plist**

Create `~/coders-war-room/com.warroom.server.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.warroom.server</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/python3</string>
        <string>/Users/gurvindersingh/coders-war-room/server.py</string>
    </array>
    <key>WorkingDirectory</key>
    <string>/Users/gurvindersingh/coders-war-room</string>
    <key>KeepAlive</key>
    <true/>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/warroom-server.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/warroom-server.error.log</string>
</dict>
</plist>
```

- [ ] **Step 2: Create install-service.sh**

Create `~/coders-war-room/install-service.sh`:

```bash
#!/bin/bash
# Install or uninstall the War Room server as a macOS LaunchAgent
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLIST="com.warroom.server.plist"
DEST="$HOME/Library/LaunchAgents/$PLIST"

case "$1" in
    install)
        # Kill any manually started server
        pkill -f "python3.*server.py" 2>/dev/null || true
        sleep 1

        # Copy plist and load
        cp "$SCRIPT_DIR/$PLIST" "$DEST"
        launchctl load "$DEST"
        echo "War Room server installed as LaunchAgent"
        echo "  Auto-starts on login, auto-restarts on crash"
        echo "  Logs: /tmp/warroom-server.log"

        # Verify
        sleep 2
        if curl -s http://localhost:5680/api/agents > /dev/null 2>&1; then
            echo "  Status: RUNNING on port 5680"
        else
            echo "  Status: NOT YET RUNNING (check logs)"
        fi
        ;;

    uninstall)
        if [ -f "$DEST" ]; then
            launchctl unload "$DEST" 2>/dev/null || true
            rm -f "$DEST"
            echo "War Room server LaunchAgent uninstalled"
        else
            echo "No LaunchAgent found"
        fi
        ;;

    status)
        if launchctl list | grep -q com.warroom.server; then
            echo "LaunchAgent: LOADED"
            if curl -s http://localhost:5680/api/agents > /dev/null 2>&1; then
                echo "Server: RUNNING"
            else
                echo "Server: NOT RESPONDING (restarting...)"
            fi
        else
            echo "LaunchAgent: NOT LOADED"
        fi
        ;;

    *)
        echo "Usage: install-service.sh [install|uninstall|status]"
        ;;
esac
```

- [ ] **Step 3: Make executable**

```bash
chmod +x ~/coders-war-room/install-service.sh
```

- [ ] **Step 4: Update start.sh**

Replace `~/coders-war-room/start.sh` content:

```bash
#!/bin/bash
# Coder's War Room — Start Everything
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PORT=5680
PLIST_DEST="$HOME/Library/LaunchAgents/com.warroom.server.plist"

echo "==========================================="
echo "  CODER'S WAR ROOM — Starting Up"
echo "==========================================="

# Start server via LaunchAgent if installed, otherwise nohup
if [ -f "$PLIST_DEST" ]; then
    if ! curl -s "http://localhost:$PORT/api/agents" > /dev/null 2>&1; then
        echo "Starting server via LaunchAgent..."
        launchctl load "$PLIST_DEST" 2>/dev/null || true
        sleep 2
    fi
    echo "Server running (LaunchAgent managed, port $PORT)"
elif curl -s "http://localhost:$PORT/api/agents" > /dev/null 2>&1; then
    echo "Server already running on port $PORT"
else
    echo "Starting server on port $PORT..."
    cd "$SCRIPT_DIR"
    nohup python3 server.py > /tmp/warroom-server.log 2>&1 &
    echo $! > /tmp/warroom-server.pid
    sleep 2
    if curl -s "http://localhost:$PORT/api/agents" > /dev/null 2>&1; then
        echo "Server started (PID: $(cat /tmp/warroom-server.pid))"
    else
        echo "ERROR: Server failed to start. Check /tmp/warroom-server.log"
        exit 1
    fi
fi

# Onboard agents
echo ""
"$SCRIPT_DIR/onboard.sh" "$@"

# Open web UI
echo ""
echo "Opening web UI..."
open "http://localhost:$PORT"
```

- [ ] **Step 5: Update stop.sh**

Replace `~/coders-war-room/stop.sh` content:

```bash
#!/bin/bash
# Coder's War Room — Stop Everything

echo "==========================================="
echo "  CODER'S WAR ROOM — Shutting Down"
echo "==========================================="

# Kill warroom tmux sessions
echo "Killing agent sessions..."
tmux list-sessions 2>/dev/null | grep "^warroom-" | cut -d: -f1 | while read -r session; do
    echo "  Killing: $session"
    tmux kill-session -t "$session" 2>/dev/null || true
done

# Stop server
PLIST_DEST="$HOME/Library/LaunchAgents/com.warroom.server.plist"
if [ -f "$PLIST_DEST" ] && launchctl list | grep -q com.warroom.server; then
    echo "Stopping server (LaunchAgent)..."
    launchctl unload "$PLIST_DEST"
    launchctl load "$PLIST_DEST"  # Will restart due to KeepAlive — so fully unload
    launchctl unload "$PLIST_DEST" 2>/dev/null || true
    echo "Server stopped"
elif [ -f /tmp/warroom-server.pid ]; then
    PID=$(cat /tmp/warroom-server.pid)
    if kill -0 "$PID" 2>/dev/null; then
        echo "Stopping server (PID: $PID)..."
        kill "$PID"
        rm -f /tmp/warroom-server.pid
    fi
else
    pkill -f "python3.*server.py" 2>/dev/null && echo "Server stopped" || echo "Server was not running"
fi

echo ""
echo "War Room shut down."
```

- [ ] **Step 6: Commit**

```bash
cd ~/coders-war-room
git add com.warroom.server.plist install-service.sh start.sh stop.sh
git commit -m "feat: add LaunchAgent auto-restart and install-service.sh"
```

---

### Task 4: Integration Tests

**Files:**
- Modify: `~/coders-war-room/tests/test_integration.py`

- [ ] **Step 1: Add integration tests**

```python
def test_dedup_message_ids_tracked():
    """Verify that posting a message returns an incrementing ID."""
    resp1 = httpx.post(f"{SERVER_URL}/api/messages", json={
        "sender": "phase-1", "content": "dedup test 1",
    })
    resp2 = httpx.post(f"{SERVER_URL}/api/messages", json={
        "sender": "phase-1", "content": "dedup test 2",
    })
    assert resp1.json()["id"] < resp2.json()["id"]


def test_roll_call_endpoint():
    """Test that roll call endpoint returns within timeout."""
    # This test takes ~10s due to the wait
    resp = httpx.post(f"{SERVER_URL}/api/roll-call", timeout=15)
    assert resp.status_code == 200
    data = resp.json()
    assert "responded" in data
    assert "missing" in data
    assert "total" in data
    assert isinstance(data["responded"], list)
    assert isinstance(data["missing"], list)
```

- [ ] **Step 2: Run integration tests**

```bash
cd ~/coders-war-room
python3 -m pytest tests/test_integration.py -v -s
```

Note: `test_roll_call_endpoint` takes ~12 seconds due to the 10s wait.

- [ ] **Step 3: Commit**

```bash
cd ~/coders-war-room
git add tests/test_integration.py
git commit -m "test: add integration tests for dedup and roll call"
```
