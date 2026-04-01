#!/bin/bash
# Coder's War Room — Agent Onboarding
# Creates tmux sessions, starts Claude Code, injects agent identity.
#
# Usage:
#   ./onboard.sh                  # Onboard all agents from config.yaml
#   ./onboard.sh phase-1 phase-2  # Onboard specific agents only

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config.yaml"
WARROOM_SH="$SCRIPT_DIR/warroom.sh"
SERVER_URL="http://localhost:5680"

get_config() {
    python3 -c "
import yaml, json, sys
with open('$CONFIG_FILE') as f:
    config = yaml.safe_load(f)
print(json.dumps(config))
"
}

CONFIG_JSON=$(get_config)
PROJECT_PATH=$(echo "$CONFIG_JSON" | python3 -c "import sys,json,os; print(os.path.expanduser(json.load(sys.stdin)['project_path']))")

get_agents() {
    local filter="$1"
    echo "$CONFIG_JSON" | python3 -c "
import sys, json
config = json.load(sys.stdin)
agents = config.get('agents', [])
filter_names = '$filter'.split() if '$filter' else []
for a in agents:
    if not filter_names or a['name'] in filter_names:
        print(f\"{a['name']}|{a['tmux_session']}|{a['role']}\")
"
}

wait_for_prompt() {
    local session="$1"
    local max_wait=30
    local waited=0

    echo "  Waiting for Claude Code to start..."
    while [ $waited -lt $max_wait ]; do
        sleep 2
        waited=$((waited + 2))

        local content
        content=$(tmux capture-pane -t "$session" -p -S -5 2>/dev/null || true)

        if echo "$content" | grep -qE '(>|Claude|/help)'; then
            echo "  Claude Code is ready (${waited}s)"
            return 0
        fi
    done

    echo "  WARNING: Timed out waiting for Claude Code (${max_wait}s). Sending onboarding anyway."
    return 0
}

onboard_agent() {
    local name="$1"
    local session="$2"
    local role="$3"

    echo ""
    echo "=== Onboarding: $name ==="

    if tmux has-session -t "$session" 2>/dev/null; then
        echo "  Killing existing session: $session"
        tmux kill-session -t "$session"
        sleep 1
    fi

    echo "  Creating tmux session: $session"
    tmux new-session -d -s "$session" -x 200 -y 50

    if [ "$name" = "supervisor" ]; then
        tmux set-option -t "$session" history-limit 50000
        echo "  Scrollback: 50000 (supervisor)"
    else
        tmux set-option -t "$session" history-limit 10000
    fi

    tmux send-keys -t "$session" "export WARROOM_AGENT_NAME=$name" Enter
    sleep 0.5

    echo "  Starting Claude Code..."
    tmux send-keys -t "$session" "cd $PROJECT_PATH && claude --dangerously-skip-permissions" Enter

    wait_for_prompt "$session"

    local onboarding
    read -r -d '' onboarding << ONBOARD_EOF || true
You are $name in the Coder's War Room — a real-time communication system for parallel Claude Code agents working on the same project.

YOUR IDENTITY: $name
YOUR ROLE: $role
PROJECT: $PROJECT_PATH

WAR ROOM PROTOCOL:
- Messages prefixed with [WARROOM @$name] are directed at you. You MUST respond and act on them.
- Messages prefixed with [WARROOM] (no specific tag) are broadcasts. Read them for context. Only respond if it directly impacts your current work. If not relevant, just say "Noted" and continue your work. Do NOT post acknowledgements to the war room.
- Messages prefixed with [WARROOM SYSTEM] are informational. Do not respond.
- To send a message to the war room, run: $WARROOM_SH post "your message"
- To send a direct message: $WARROOM_SH post --to <agent-name> "your message"
- To check recent messages: $WARROOM_SH history
- Keep war room messages concise. This is a chat, not a document.
- When you complete a task or hit a blocker, post it to the war room immediately.

Acknowledge with your name and role, then wait for instructions.
ONBOARD_EOF

    tmux set-buffer -b warroom-onboard "$onboarding"
    tmux paste-buffer -b warroom-onboard -t "$session"
    sleep 0.5
    tmux send-keys -t "$session" Enter

    echo "  Onboarded: $name"

    curl -s -X POST "$SERVER_URL/api/messages" \
        -H "Content-Type: application/json" \
        -d "{\"sender\": \"system\", \"content\": \"$name has joined the war room\", \"type\": \"system\"}" \
        > /dev/null 2>&1 || true
}

# Main
echo "==========================================="
echo "  CODER'S WAR ROOM — Agent Onboarding"
echo "==========================================="
echo "Project: $PROJECT_PATH"
echo ""

if ! command -v tmux &> /dev/null; then
    echo "ERROR: tmux is not installed. Run: brew install tmux"
    exit 1
fi

if ! curl -s "$SERVER_URL/api/agents" > /dev/null 2>&1; then
    echo "ERROR: War Room server not running at $SERVER_URL"
    echo "Start it first: python3 $SCRIPT_DIR/server.py &"
    exit 1
fi

FILTER="${*}"
while IFS='|' read -r name session role; do
    onboard_agent "$name" "$session" "$role"
done < <(get_agents "$FILTER")

echo ""
echo "==========================================="
echo "  All agents onboarded!"
echo "  Web UI: $SERVER_URL"
echo "  tmux sessions: tmux ls | grep warroom"
echo "==========================================="
