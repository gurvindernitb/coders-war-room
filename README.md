# Coder's War Room

A real-time coordination system for multiple Claude Code agents working on the same project. Built in a day. Ships with a web UI, tmux-based agent management, and a full communication pipeline.

## What It Does

- **Web UI** at `localhost:5680` — group chat, agent dashboard, file browser
- **tmux sessions** per agent — each agent runs Claude Code in its own terminal
- **Real-time dispatch** — messages delivered to agents automatically via tmux paste-buffer
- **Live dashboard** — see what every agent is doing, their progress, blockers, and status
- **File browser** — browse project files, drag-and-drop to chat or agent cards
- **One-click pop-out** — open any agent's CLI in Warp/Terminal from the web UI
- **Agent lifecycle** — onboard, de-board, recover, remove — all from the browser
- **Role-based pipeline** — supervisor, scout, engineer, QA, git-agent, chronicler

## Quick Start

```bash
# 1. Clone and install
cd ~/coders-war-room
pip3 install -r requirements.txt
brew install tmux  # if not installed

# 2. Start the server
python3 server.py &

# 3. Onboard agents
./onboard.sh

# 4. Open the web UI
open http://localhost:5680
```

Or use the one-command startup:

```bash
./start.sh
```

## Architecture

```
┌──────────────┐     WebSocket      ┌──────────────┐     tmux dispatch
│  Web Chat UI │◄──────────────────►│   FastAPI     │────────────────────►  Agent 1 (tmux)
│  (browser)   │                    │   Server      │────────────────────►  Agent 2 (tmux)
└──────────────┘                    │  port 5680    │────────────────────►  Agent 3 (tmux)
                                    │               │         ...
┌──────────────┐   POST /api/*      │               │────────────────────►  Agent N (tmux)
│  warroom.sh  │───────────────────►│               │
│  (agent CLI) │                    └───────┬───────┘
└──────────────┘                            │
                                     ┌──────┴──────┐
                                     │   SQLite    │
                                     │  warroom.db │
                                     └─────────────┘
```

**Three-column web UI:** Agents (left) | Chat (center) | Files (right)

See [ARCHITECTURE.md](ARCHITECTURE.md) for the full technical deep-dive.

## Agent Roles

| Role | Agent Name | What They Do |
|------|-----------|-------------|
| **Supervisor** | `supervisor` | Decomposes work, assigns tasks, approves merges. Never codes. |
| **Scout** | `scout` | Research, blast radius analysis, dependency verification. Never codes. |
| **Engineer** | `engineer-1`, `engineer-2` | TDD implementation in isolated worktrees. Up to 2 in parallel. |
| **QA** | `qa` | Full verification suite. PASS or FAIL with evidence. Never codes. |
| **Git Agent** | `git-agent` | All git operations. 6 commit points per task lifecycle. |
| **Chronicler** | `chronicler` | Silent observer. Detects spec drift, tracks metrics, proposes improvements. |

## Web UI Features

### Agent Dashboard (left panel)
- Live presence: green (idle), yellow (working), cyan (thinking), red (blocked/dead)
- Progress bars and ETA when agents report status
- Blocker detection with auto-DM to the blocking agent
- Staleness detection (5+ min same state)
- De-board / re-board / recover / remove lifecycle
- Drag to reorder agent cards
- Click `cli` to pop out agent in Warp terminal

### Chat (center panel)
- Real-time WebSocket messaging
- @mention targeting via dropdown
- Color-coded messages per agent
- Message grouping for same sender
- Dynamic border colors matching agent identity

### File Browser (right panel)
- Project directory tree with expandable folders
- Click file → opens in system default editor
- Click .md file → renders in browser with dark theme
- Drag file to chat → inserts path
- Drag file to agent card → auto-composes @agent message

### Agent Onboarding (slide-out drawer)
- Role type dropdown with 7 presets (auto-fills description + instructions)
- Directory browser for choosing working directory
- Model selection (Opus/Sonnet/Haiku)
- Permission toggle

## CLI Reference

```bash
# Messaging
warroom.sh post "message"                    # Broadcast to all
warroom.sh post --to engineer-1 "message"    # Direct message
warroom.sh history                           # Recent messages
warroom.sh mentions                          # Messages for you

# Status
warroom.sh status "fixing imports" --progress 60 --eta 5m
warroom.sh status --blocked engineer-1 "needs config change"
warroom.sh status --unblocked
warroom.sh status --clear
warroom.sh status --show

# Lifecycle
warroom.sh deboard                           # Leave room (keep session)
warroom.sh reboard                           # Rejoin room
warroom.sh roll-call                         # Check who's alive
warroom.sh attach engineer-1                 # Pop out in Warp

# Identity (auto-detected from tmux session name)
warroom.sh                                   # Show help + current identity
```

## Server Management

```bash
# Manual start/stop
./start.sh                     # Start server + onboard agents + open UI
./stop.sh                      # Stop everything

# Auto-restart (LaunchAgent)
./install-service.sh install   # Auto-start on login, auto-restart on crash
./install-service.sh status    # Check if running
./install-service.sh uninstall # Remove auto-restart

# The web UI header shows: uptime, LaunchAgent status, Restart, Logs
```

## API Endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET | `/` | Web UI |
| GET | `/api/agents` | List all agents with presence |
| POST | `/api/agents/create` | Create a new agent |
| POST | `/api/agents/{name}/status` | Set agent status |
| GET | `/api/agents/{name}/status` | Get agent card state |
| POST | `/api/agents/{name}/deboard` | De-board agent |
| POST | `/api/agents/{name}/reboard` | Re-board agent |
| POST | `/api/agents/{name}/recover` | Recover dead session |
| DELETE | `/api/agents/{name}/remove` | Permanently remove agent |
| POST | `/api/agents/{name}/attach` | Pop out in terminal |
| POST | `/api/messages` | Post a message |
| GET | `/api/messages` | Get message history |
| GET | `/message/{id}` | Get full message text |
| GET | `/api/files?path=.` | Browse project files |
| POST | `/api/files/open` | Open file in editor |
| GET | `/api/browse?path=~` | Browse home directories |
| POST | `/api/roll-call` | Check which agents are alive |
| GET | `/api/server/health` | Server uptime and status |
| POST | `/api/server/restart` | Graceful restart |
| GET | `/api/server/logs` | View server logs |
| GET | `/preview/{path}` | Render markdown file |
| WS | `/ws` | WebSocket for real-time updates |

## Configuration

`config.yaml` defines the agent roster:

```yaml
port: 5680
project_path: ~/contextualise

agents:
  - name: engineer-1
    role: "Implementation. TDD workflow, isolated worktrees."
    tmux_session: warroom-engineer-1
    role_type: engineer
    instructions: ENGINEER_INSTRUCTIONS.md
    owns: []
```

## File Structure

```
coders-war-room/
├── server.py              # FastAPI server (1300 lines) — API, WebSocket, tmux dispatch
├── static/index.html      # Web UI (2100 lines) — three-column layout, all vanilla JS
├── warroom.sh             # Agent CLI (320 lines)
├── config.yaml            # Agent roster
├── startup.md             # Universal agent protocol
├── onboarding-prompt.md   # Onboarding template with placeholders
├── onboard.sh             # Mass agent onboarding script
├── join.sh                # Join existing session to war room
├── start.sh               # One-command startup
├── stop.sh                # One-command shutdown
├── install-service.sh     # LaunchAgent management
├── com.warroom.server.plist  # macOS LaunchAgent definition
├── requirements.txt       # Python dependencies
├── tests/
│   ├── test_api.py        # Unit tests (20 tests)
│   ├── test_integration.py # Integration tests (13 tests)
│   └── conftest.py        # Test fixtures
└── docs/
    └── superpowers/
        ├── specs/          # 6 design specs
        └── plans/          # 6 implementation plans
```

## Tech Stack

- **Python 3.12** + FastAPI + uvicorn + aiosqlite
- **SQLite** with WAL mode for concurrent access
- **tmux** for agent session management
- **Vanilla HTML/CSS/JS** — no frameworks, no build step
- **macOS** LaunchAgent for auto-restart
- **Warp** terminal integration (falls back to Terminal.app)

## Requirements

- macOS (LaunchAgent, Warp support)
- Python 3.12+
- tmux
- Claude Code CLI (`claude`)
- Claude Max subscription (agents use the CLI, not API tokens)

## Tests

```bash
# Unit tests (fast, no server needed)
python3 -m pytest tests/test_api.py -v

# Integration tests (starts isolated server on port 5681)
python3 -m pytest tests/test_integration.py -v -s

# All tests
python3 -m pytest tests/ -v
```

33 tests covering: message CRUD, agent lifecycle, status board, file browser, security boundaries, deduplication, roll call.

## License

MIT

## Built With

Built in one session with [Claude Code](https://claude.ai/code) (Opus 4.6) using the [Superpowers](https://github.com/anthropics/claude-plugins) plugin for TDD, planning, and code review.
