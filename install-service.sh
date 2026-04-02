#!/bin/bash
# Install or uninstall the War Room server as a macOS LaunchAgent
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLIST="com.warroom.server.plist"
DEST="$HOME/Library/LaunchAgents/$PLIST"

case "$1" in
    install)
        pkill -f "python3.*server.py" 2>/dev/null || true
        sleep 1
        cp "$SCRIPT_DIR/$PLIST" "$DEST"
        launchctl load "$DEST"
        echo "War Room server installed as LaunchAgent"
        echo "  Auto-starts on login, auto-restarts on crash"
        echo "  Logs: /tmp/warroom-server.log"
        sleep 2
        if curl -s http://localhost:5680/api/agents > /dev/null 2>&1; then
            echo "  Status: RUNNING on port 5680"
        else
            echo "  Status: NOT YET RUNNING (check logs)"
        fi
        ;;
    uninstall)
        if [ -f "$DEST" ]; then
            launchctl bootout "gui/$(id -u)" "$DEST" 2>/dev/null || launchctl unload "$DEST" 2>/dev/null || true
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
                echo "Server: NOT RESPONDING"
            fi
        else
            echo "LaunchAgent: NOT LOADED"
        fi
        ;;
    *)
        echo "Usage: install-service.sh [install|uninstall|status]"
        ;;
esac
