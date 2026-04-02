# Message Quality — Design Spec

**Date:** 2026-04-02
**Goal:** Fix message deduplication, add roll call command, and auto-restart the server via LaunchAgent.
**Scope:** Three focused infrastructure fixes based on agent feedback from the first War Room session.

---

## 1. Message Deduplication

### Problem

Agents received the same messages 15+ times during the first session. Root causes:
- `flush_queues_loop` can re-deliver messages if the server restarts while messages are queued
- No protection against the same message being dispatched twice to the same agent
- Integration tests polluted the chat with repeated test messages

### Solution

Track the last message ID dispatched to each agent. Only send messages with IDs higher than the last-seen ID.

**Server-side state:**

```python
agent_last_seen_id: dict[str, int] = {}
```

**Dispatch filter in `dispatch_to_agents()`:**

Before sending a message to an agent, check:
```python
if msg["id"] <= agent_last_seen_id.get(name, 0):
    continue  # Already delivered
```

After successful delivery:
```python
agent_last_seen_id[name] = msg["id"]
```

**Queue filter in `flush_queues_loop()`:**

When flushing queued messages, filter out any with IDs at or below the agent's last-seen:
```python
messages = [m for m in queued if m["id"] > agent_last_seen_id.get(name, 0)]
```

**On server restart:**

Initialize `agent_last_seen_id` from the latest message ID in SQLite:
```python
async def get_latest_message_id() -> int:
    async with aiosqlite.connect(DB_PATH) as db:
        cursor = await db.execute("SELECT MAX(id) FROM messages")
        row = await cursor.fetchone()
        return row[0] or 0
```

Set all agents' last-seen to this value on boot. This prevents replaying the entire message history on restart.

**No changes to CLI or web UI.** Dedup is purely in the tmux dispatch path.

---

## 2. Roll Call

### Problem

No way to quickly check which agents are alive and responsive. The user had to manually type "who's here?" and wait for responses.

### Solution

A `warroom.sh roll-call` command and `POST /api/roll-call` endpoint.

**Flow:**

1. User runs `warroom.sh roll-call` or clicks "Roll Call" button in web UI header
2. Server posts system message: `[ROLL CALL] All agents, report in.`
3. Dispatches to all in-room agents via tmux
4. Waits 10 seconds
5. Scans messages from the last 10 seconds for replies from each agent
6. Posts a summary system message:
   ```
   [ROLL CALL] 6/8 responded: phase-1, phase-3, phase-4, phase-5, phase-6, git-agent. Missing: supervisor, phase-2
   ```

**API:**

```
POST /api/roll-call
```

No request body. Returns after ~12 seconds (10s wait + processing):

```json
{
  "responded": ["phase-1", "phase-3", "phase-4", "phase-5", "phase-6", "git-agent"],
  "missing": ["supervisor", "phase-2"],
  "total": 8
}
```

**CLI:**

```bash
warroom.sh roll-call
```

Output:
```
Roll call sent. Waiting 10s for responses...
6/8 responded: phase-1, phase-3, phase-4, phase-5, phase-6, git-agent
Missing: supervisor, phase-2
```

**Web UI:**

A "Roll Call" button in the header, next to the LIVE badge. Clicking it sends `POST /api/roll-call`. The result appears as a system message in chat.

---

## 3. Auto-Restart via LaunchAgent

### Problem

The server crashed mid-session and agents couldn't communicate until manually restarted.

### Solution

A macOS LaunchAgent that keeps the server running.

**Plist:** `~/Library/LaunchAgents/com.warroom.server.plist`

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

**Install script:** `install-service.sh`

```bash
cp com.warroom.server.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.warroom.server.plist
```

**Updated scripts:**

- `start.sh`: checks if launchd service is running, starts it if not
- `stop.sh`: `launchctl unload` to stop the service

---

## What This Does NOT Include

- No delivery confirmations (low impact, agents function without them)
- No separate channels (deferred — single channel works for current team size)
- No message expiry or cleanup (SQLite handles storage fine)
- No rate limiting on messages (not a problem at current scale)
