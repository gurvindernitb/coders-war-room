# Contributing

## Project Structure

```
server.py          — The entire backend (FastAPI + WebSocket + tmux dispatch)
static/index.html  — The entire frontend (vanilla HTML/CSS/JS)
warroom.sh         — Agent CLI tool
config.yaml        — Agent roster and settings
```

This is intentionally a small-file project. server.py and index.html are large single files because the system has many interconnected features that benefit from being in one place. Do not split them unless a clear boundary emerges.

## Development Setup

```bash
cd ~/coders-war-room
pip3 install -r requirements.txt
brew install tmux
```

## Making Changes

### Backend (server.py)

1. Read the current code — understand the globals, endpoints, and background loops
2. Write a failing test in `tests/test_api.py`
3. Implement the change
4. Run tests: `python3 -m pytest tests/test_api.py -v`
5. Test against the live server if the change affects tmux dispatch

### Frontend (static/index.html)

1. The server serves this file directly via `GET /`
2. Changes are live on page refresh (no build step)
3. All state comes from WebSocket pushes — the frontend is a thin renderer
4. Use existing CSS variables from `:root` — don't introduce new colors
5. Follow the existing pattern: JetBrains Mono for UI elements, Source Sans 3 for message content

### CLI (warroom.sh)

1. Each subcommand is a function + a case entry
2. Agent identity is auto-detected from the tmux session name
3. Test by running with `WARROOM_AGENT_NAME=test ./warroom.sh <command>`

## Testing

```bash
# Unit tests — fast, isolated, no server needed
python3 -m pytest tests/test_api.py -v

# Integration tests — starts isolated server on port 5681
# SAFE: never touches the live server on 5680
python3 -m pytest tests/test_integration.py -v -s

# All tests
python3 -m pytest tests/ -v
```

### Test Safety

Integration tests run on **port 5681** with a temporary database. They never kill or interfere with the live server on port 5680. This is enforced in the test fixture — do not change it.

### Writing Tests

- Unit tests use `httpx.AsyncClient` with `ASGITransport` — no real server needed
- Integration tests use `httpx` against a real server subprocess
- Use `monkeypatch` in conftest.py to isolate state between tests
- Agent names in tests must match config.yaml (currently: supervisor, scout, engineer-1, engineer-2, qa, git-agent, chronicler)

## Config Changes

When modifying `config.yaml`:
- Agent names must be lowercase, hyphenated
- `tmux_session` must be `warroom-<name>`
- `role_type` maps to the role preset in the web UI
- `instructions` maps to a file in the project's `docs/` directory
- `owns: []` — static file ownership was removed in Package E

## Key Conventions

- **No frameworks** in the frontend — vanilla JS only
- **No build step** — edit and refresh
- **Single-file backend** — server.py is the source of truth
- **tmux session names** always prefixed with `warroom-`
- **Agent identity** derived from tmux session name (strip `warroom-` prefix)
- **Messages** stored in SQLite with WAL mode
- **WebSocket** pushes agent status every 2 seconds
- **CSS variables** in `:root` — use them, don't hardcode colors

## Commit Messages

```
feat: add new feature
fix: bug fix
test: add or update tests
docs: documentation only
chore: maintenance (gitignore, deps, etc.)
```

## Don't

- Don't use `pkill -f "python3.*server.py"` — use PID files or LaunchAgent
- Don't run integration tests against port 5680 (live server)
- Don't split server.py or index.html without strong justification
- Don't add npm/webpack/vite — this is intentionally vanilla
- Don't add authentication — this is a local-only tool
