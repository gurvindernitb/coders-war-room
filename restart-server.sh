#!/bin/bash
# Coder's War Room — Robust Server Restart
# Kills ALL processes on port 5680, waits for port release, starts fresh.
# Does NOT touch tmux sessions — agents survive.

set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PORT=5680
PID_FILE="/tmp/warroom-server.pid"

echo "=== War Room Server Restart ==="

# Kill anything on the port (try graceful first, then force)
PIDS=$(lsof -ti :$PORT 2>/dev/null || true)
if [ -n "$PIDS" ]; then
    echo "Stopping processes on port $PORT: $PIDS"
    echo "$PIDS" | xargs kill -15 2>/dev/null || true
    sleep 2
    # Check if still alive — force kill
    PIDS=$(lsof -ti :$PORT 2>/dev/null || true)
    if [ -n "$PIDS" ]; then
        echo "Force killing: $PIDS"
        echo "$PIDS" | xargs kill -9 2>/dev/null || true
        sleep 1
    fi
fi

# Verify port is free (retry up to 5 times)
for i in 1 2 3 4 5; do
    if ! lsof -ti :$PORT >/dev/null 2>&1; then
        break
    fi
    if [ "$i" -eq 5 ]; then
        echo "ERROR: Port $PORT still in use after 5 retries. Aborting."
        exit 1
    fi
    echo "Port still busy, waiting... ($i/5)"
    sleep 1
done
echo "Port $PORT is free."

# Start server
cd "$SCRIPT_DIR"
nohup python3 server.py > /tmp/warroom-server.log 2>&1 &
SERVER_PID=$!
echo $SERVER_PID > "$PID_FILE"
echo "Server PID: $SERVER_PID"
sleep 3

# Verify server is healthy
HEALTH=$(curl -s "http://localhost:$PORT/api/server/health" 2>/dev/null || echo "{}")
AGENT_COUNT=$(echo "$HEALTH" | python3 -c "import sys,json; print(json.load(sys.stdin).get('agent_count', 0))" 2>/dev/null || echo "0")
ALIVE=$(echo "$HEALTH" | python3 -c "import sys,json; print(json.load(sys.stdin).get('agents_alive', 0))" 2>/dev/null || echo "0")

if [ "$AGENT_COUNT" -gt 0 ]; then
    echo "Server started. $AGENT_COUNT agents registered, $ALIVE alive."
else
    # Check if tmux sessions exist but agents weren't recovered
    TMUX_COUNT=$(tmux list-sessions -F '#{session_name}' 2>/dev/null | grep -c '^warroom-' || echo "0")
    if [ "$TMUX_COUNT" -gt 0 ]; then
        echo "WARNING: $TMUX_COUNT tmux sessions found but 0 agents recovered."
        echo "This should not happen — check /tmp/warroom-server.log"
    else
        echo "Server started. No tmux sessions found (no agents to recover)."
    fi
fi

echo "=== Done ==="
