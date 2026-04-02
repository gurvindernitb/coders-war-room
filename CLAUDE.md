# Coder's War Room — Context for Claude

> If you're reading this, you're working on the War Room coordination system.

## What This Is

A local real-time chat + dashboard for orchestrating multiple Claude Code agents working on the same project. Built with FastAPI, SQLite, tmux, and vanilla HTML/JS.

**Single-file architecture:** `server.py` is the backend, `static/index.html` is the frontend. Both are large but intentionally monolithic — the features are tightly interconnected.

## Key Files

| File | Lines | What it does |
|------|-------|-------------|
| `server.py` | ~1300 | FastAPI server: REST API, WebSocket, tmux dispatch, background loops |
| `static/index.html` | ~2100 | Web UI: three-column layout, agent dashboard, chat, file browser |
| `warroom.sh` | ~320 | Agent CLI: post, history, status, roll-call, attach |
| `config.yaml` | ~57 | Agent roster with role_type and instructions fields |
| `onboard.sh` | ~240 | Mass agent onboarding via tmux |
| `startup.md` | ~70 | Universal agent protocol (read by every agent) |
| `onboarding-prompt.md` | ~31 | Template with {{placeholders}} for agent identity |

## How It Works

1. Server runs on port 5680, serves the web UI and API
2. Each agent is a Claude Code instance in a named tmux session (`warroom-<name>`)
3. Messages are stored in SQLite, pushed via WebSocket to the web UI
4. Messages are dispatched to agents by pasting into their tmux sessions
5. The server checks if agents are "ready" (not busy) before dispatching

## MUST

- Run tests before committing: `python3 -m pytest tests/ -v`
- Integration tests use port 5681 (never touch port 5680)
- Use existing CSS variables — don't hardcode colors
- Keep server.py and index.html as single files
- Agent names in tests must match config.yaml

## MUST NOT

- Never use `pkill -f "python3.*server.py"` — use PID or LaunchAgent
- Never add npm/webpack/build tools — this is vanilla JS
- Never add authentication — local-only tool
- Never split server.py without strong justification

## Architecture Reference

See `ARCHITECTURE.md` for the full technical deep-dive including data flow diagrams, state management, and WebSocket protocol.
