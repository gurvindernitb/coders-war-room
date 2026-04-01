#!/bin/bash
# Coder's War Room — Start Everything
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PORT=5680

echo "==========================================="
echo "  CODER'S WAR ROOM — Starting Up"
echo "==========================================="

# Check if server is already running
if curl -s "http://localhost:$PORT/api/agents" > /dev/null 2>&1; then
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

# Onboard agents (pass through any arguments for selective onboarding)
echo ""
"$SCRIPT_DIR/onboard.sh" "$@"

# Open web UI
echo ""
echo "Opening web UI..."
open "http://localhost:$PORT"
