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

# Kill server
if [ -f /tmp/warroom-server.pid ]; then
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
