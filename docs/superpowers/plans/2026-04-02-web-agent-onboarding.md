# Web-Based Agent Onboarding Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create, configure, and launch new Claude Code agents directly from the War Room web UI — directory browser, onboarding form, and dynamic agent roster.

**Architecture:** Two new API endpoints (`GET /api/browse`, `POST /api/agents/create`) handle directory listing and agent creation. A reconciliation scan on server boot re-adopts orphaned tmux sessions. A slide-out drawer in the HTML provides the form. A placeholder `startup.md` is created for shared protocol.

**Tech Stack:** Python 3.12, FastAPI, aiosqlite, tmux, vanilla HTML/CSS/JS

**Design Spec:** `docs/superpowers/specs/2026-04-02-web-agent-onboarding-design.md`

---

## File Structure

| File | Responsibility | Action |
|------|---------------|--------|
| `server.py` | Browse API, create API, reconciliation scan, dynamic roster | Modify |
| `static/index.html` | Slide-out drawer, onboarding form, directory picker, dynamic sidebar | Modify |
| `startup.md` | Global agent protocol file (placeholder) | Create |
| `tests/test_api.py` | Tests for browse and create endpoints | Modify |
| `tests/conftest.py` | Patch new globals (AGENT_DIRS, PROJECT_PATH) | Modify |

---

### Task 1: Directory Browse API

**Files:**
- Modify: `~/coders-war-room/server.py`
- Modify: `~/coders-war-room/tests/test_api.py`

- [ ] **Step 1: Write the failing test**

Add to `~/coders-war-room/tests/test_api.py`:

```python
@pytest.mark.asyncio
async def test_browse_home():
    from server import app
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        import os
        home = os.path.expanduser("~")
        resp = await client.get(f"/api/browse?path={home}")
        assert resp.status_code == 200
        data = resp.json()
        assert data["current"] == home
        assert "parent" in data
        assert "directories" in data
        assert isinstance(data["directories"], list)
        # Should have at least one directory
        assert len(data["directories"]) > 0
        # Each entry should have name and path
        for d in data["directories"]:
            assert "name" in d
            assert "path" in d
        # Should NOT contain hidden dirs (except .claude)
        names = [d["name"] for d in data["directories"]]
        assert ".Trash" not in names
        # Should NOT contain system dirs
        assert "Library" not in names
        assert "Applications" not in names


@pytest.mark.asyncio
async def test_browse_security_boundary():
    from server import app
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        # Trying to browse outside home should fail
        resp = await client.get("/api/browse?path=/etc")
        assert resp.status_code == 403


@pytest.mark.asyncio
async def test_browse_nonexistent():
    from server import app
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        resp = await client.get("/api/browse?path=/Users/gurvindersingh/nonexistent_dir_xyz")
        assert resp.status_code == 404
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd ~/coders-war-room
python3 -m pytest tests/test_api.py::test_browse_home tests/test_api.py::test_browse_security_boundary tests/test_api.py::test_browse_nonexistent -v
```

Expected: FAIL — no route `/api/browse`

- [ ] **Step 3: Implement the browse endpoint**

Add to `~/coders-war-room/server.py`, after the `/api/agents` endpoint and before the deboard/reboard endpoints:

```python
import os

SYSTEM_DIRS = {"Library", "Applications", "Public", "Movies", "Music", "Pictures"}
HOME_DIR = str(Path.home())


@app.get("/api/browse")
async def browse_directory(path: str = "~"):
    """List directories in the given path for the directory picker."""
    expanded = str(Path(path).expanduser().resolve())

    # Security: must be under home directory
    if not expanded.startswith(HOME_DIR):
        return JSONResponse({"error": "Path must be under home directory"}, status_code=403)

    if not Path(expanded).is_dir():
        return JSONResponse({"error": f"Directory not found: {path}"}, status_code=404)

    parent = str(Path(expanded).parent)
    if not parent.startswith(HOME_DIR):
        parent = HOME_DIR  # Don't navigate above home

    directories = []
    try:
        for entry in sorted(Path(expanded).iterdir()):
            if not entry.is_dir():
                continue
            name = entry.name
            # Skip hidden dirs (except .claude)
            if name.startswith(".") and name != ".claude":
                continue
            # Skip system dirs at home level
            if expanded == HOME_DIR and name in SYSTEM_DIRS:
                continue
            directories.append({"name": name, "path": str(entry)})
    except PermissionError:
        return JSONResponse({"error": "Permission denied"}, status_code=403)

    return {"current": expanded, "parent": parent, "directories": directories}
```

- [ ] **Step 4: Add the `os` import at top of server.py if not present**

Check line 1-10 of server.py — `os` may not be imported. Add `import os` after `import json` if missing.

- [ ] **Step 5: Run tests to verify they pass**

```bash
cd ~/coders-war-room
python3 -m pytest tests/test_api.py -v
```

Expected: All tests PASS (existing 5 + 3 new = 8).

- [ ] **Step 6: Commit**

```bash
cd ~/coders-war-room
git add server.py tests/test_api.py
git commit -m "feat: add directory browse API for agent onboarding"
```

---

### Task 2: Agent Creation API

**Files:**
- Modify: `~/coders-war-room/server.py`
- Modify: `~/coders-war-room/tests/test_api.py`
- Modify: `~/coders-war-room/tests/conftest.py`

- [ ] **Step 1: Write the failing test**

Add to `~/coders-war-room/tests/test_api.py`:

```python
@pytest.mark.asyncio
async def test_create_agent():
    from server import app, AGENTS, AGENT_NAMES, AGENT_SESSIONS, AGENT_DIRS, agent_membership
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        import os
        resp = await client.post("/api/agents/create", json={
            "name": "test-agent",
            "directory": os.path.expanduser("~"),
            "role": "Test agent for unit tests",
            "initial_prompt": "",
            "model": "opus",
            "skip_permissions": True,
        })
        assert resp.status_code == 200
        data = resp.json()
        assert data["status"] == "created"
        assert data["agent"]["name"] == "test-agent"
        assert data["agent"]["tmux_session"] == "warroom-test-agent"
        assert data["agent"]["in_room"] is True
        # Check it was added to in-memory roster
        assert "test-agent" in AGENT_NAMES


@pytest.mark.asyncio
async def test_create_agent_duplicate_name():
    from server import app
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        # "supervisor" already exists in config.yaml
        resp = await client.post("/api/agents/create", json={
            "name": "supervisor",
            "directory": os.path.expanduser("~"),
            "role": "Duplicate",
            "model": "opus",
            "skip_permissions": True,
        })
        assert resp.status_code == 400
        assert "already exists" in resp.json()["error"]


@pytest.mark.asyncio
async def test_create_agent_invalid_name():
    from server import app
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        resp = await client.post("/api/agents/create", json={
            "name": "BAD NAME!",
            "directory": os.path.expanduser("~"),
            "role": "Bad",
            "model": "opus",
            "skip_permissions": True,
        })
        assert resp.status_code == 400


@pytest.mark.asyncio
async def test_create_agent_bad_directory():
    from server import app
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        resp = await client.post("/api/agents/create", json={
            "name": "ghost-agent",
            "directory": "/nonexistent/path",
            "role": "Ghost",
            "model": "opus",
            "skip_permissions": True,
        })
        assert resp.status_code == 400
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd ~/coders-war-room
python3 -m pytest tests/test_api.py::test_create_agent tests/test_api.py::test_create_agent_duplicate_name tests/test_api.py::test_create_agent_invalid_name tests/test_api.py::test_create_agent_bad_directory -v
```

Expected: FAIL — no route `/api/agents/create`

- [ ] **Step 3: Add the Pydantic model and create endpoint**

Add to `~/coders-war-room/server.py`, after the `MessageCreate` model:

```python
import re


class AgentCreate(BaseModel):
    name: str
    directory: str
    role: str
    initial_prompt: str = ""
    model: str = "opus"
    skip_permissions: bool = True


NAME_PATTERN = re.compile(r"^[a-z0-9][a-z0-9\-]{0,18}[a-z0-9]$")
VALID_MODELS = {"opus", "sonnet", "haiku"}
STARTUP_MD = Path(__file__).parent / "startup.md"
```

Then add the endpoint before the `/api/agents/{agent_name}/attach` route:

```python
@app.post("/api/agents/create")
async def create_agent(req: AgentCreate):
    """Create and launch a new Claude Code agent from the web UI."""
    # Validate name format
    if not NAME_PATTERN.match(req.name):
        return JSONResponse(
            {"error": "Name must be 2-20 chars, lowercase alphanumeric + hyphens, no leading/trailing hyphen"},
            status_code=400,
        )

    # Validate uniqueness (check both in-memory and config)
    if req.name in AGENT_NAMES:
        return JSONResponse({"error": f"Agent '{req.name}' already exists"}, status_code=400)

    # Validate directory
    dir_path = Path(req.directory)
    if not dir_path.is_dir():
        return JSONResponse({"error": f"Directory not found: {req.directory}"}, status_code=400)

    # Validate model
    if req.model not in VALID_MODELS:
        return JSONResponse({"error": f"Invalid model. Choose: {', '.join(VALID_MODELS)}"}, status_code=400)

    session = f"warroom-{req.name}"
    agent_dir = str(dir_path.resolve())

    try:
        # Create tmux session in the agent's working directory
        subprocess.run(
            ["tmux", "new-session", "-d", "-s", session, "-x", "200", "-y", "50", "-c", agent_dir],
            check=True, capture_output=True, timeout=5,
        )

        # Configure session
        subprocess.run(["tmux", "set-option", "-t", session, "mouse", "on"], capture_output=True, timeout=2)
        subprocess.run(["tmux", "set-option", "-t", session, "history-limit", "10000"], capture_output=True, timeout=2)
        subprocess.run(["tmux", "rename-window", "-t", session, req.name], capture_output=True, timeout=2)

        # Set env var for warroom.sh identity
        subprocess.run(
            ["tmux", "send-keys", "-t", session, f"export WARROOM_AGENT_NAME={req.name}", "Enter"],
            capture_output=True, timeout=2,
        )
        await asyncio.sleep(0.5)

        # Start Claude Code
        model_flag = f"--model {req.model}" if req.model != "opus" else ""
        perms_flag = "--dangerously-skip-permissions" if req.skip_permissions else ""
        cmd = f"cd {agent_dir} && claude {model_flag} {perms_flag}".strip()
        cmd = " ".join(cmd.split())  # normalize whitespace
        subprocess.run(
            ["tmux", "send-keys", "-t", session, cmd, "Enter"],
            capture_output=True, timeout=2,
        )

        # Wait for Claude Code to become ready (up to 30s)
        warning = None
        ready = False
        for _ in range(15):
            await asyncio.sleep(2)
            if check_agent_ready(session):
                ready = True
                break
        if not ready:
            warning = "Agent may still be starting — startup injection sent to a potentially busy terminal"

        # Inject startup
        if req.initial_prompt.strip():
            injection = f"Read ~/coders-war-room/startup.md then follow these instructions:\n\n{req.initial_prompt}"
        else:
            injection = "Read ~/coders-war-room/startup.md — you are now in the War Room. Acknowledge with your name and role, then wait for instructions."

        send_to_tmux(session, injection)

        # Add to runtime roster
        agent_entry = {
            "name": req.name,
            "role": req.role,
            "tmux_session": session,
            "dynamic": True,
        }
        AGENTS.append(agent_entry)
        AGENT_NAMES.add(req.name)
        AGENT_SESSIONS[req.name] = session
        AGENT_DIRS[req.name] = agent_dir
        agent_membership[req.name] = True

        # Announce
        saved = await save_message("system", "all", f"{req.name} has joined the war room", "system")
        await broadcast_ws({"type": "message", "message": saved})

        # Broadcast updated agent status
        activity = get_agent_activity(session)
        activity["in_room"] = True
        await broadcast_ws({"type": "agent_created", "agent": {
            "name": req.name,
            "role": req.role,
            "presence": activity["presence"],
            "activity": activity["activity"],
            "in_room": True,
            "dynamic": True,
        }})

        result = {
            "status": "created",
            "agent": {
                "name": req.name,
                "role": req.role,
                "tmux_session": session,
                "presence": activity["presence"],
                "in_room": True,
                "dynamic": True,
            },
        }
        if warning:
            result["warning"] = warning
        return result

    except subprocess.CalledProcessError as e:
        # Clean up failed session
        subprocess.run(["tmux", "kill-session", "-t", session], capture_output=True)
        return JSONResponse({"error": f"Failed to create tmux session: {e}"}, status_code=500)
```

- [ ] **Step 4: Update conftest.py to patch new globals**

In `~/coders-war-room/tests/conftest.py`, add patches for `AGENT_DIRS` and `PROJECT_PATH`:

```python
@pytest.fixture(autouse=True)
def _init_db(tmp_path, monkeypatch):
    """Use a fresh temporary DB for every test."""
    import server

    test_db = tmp_path / "test_warroom.db"
    monkeypatch.setattr(server, "DB_PATH", test_db)
    monkeypatch.setattr(server, "agent_queues", {})
    monkeypatch.setattr(server, "connected_clients", [])
    monkeypatch.setattr(server, "agent_membership", {a["name"]: True for a in server.AGENTS})
    loop = asyncio.new_event_loop()
    loop.run_until_complete(server.init_db())
    loop.close()
```

Note: The create tests need `tmux` available. In the test environment, the tmux calls will fail (no server running). The test for `test_create_agent` should be adjusted to mock subprocess OR we accept it as an integration test. For the validation tests (duplicate name, invalid name, bad directory), those fail BEFORE tmux is called, so they'll pass without mocking.

Update `test_create_agent` to be an integration-style test that's skipped if tmux isn't available:

```python
import shutil

@pytest.mark.asyncio
@pytest.mark.skipif(not shutil.which("tmux"), reason="tmux not installed")
async def test_create_agent():
    # ... (same code as above)
```

- [ ] **Step 5: Run tests**

```bash
cd ~/coders-war-room
python3 -m pytest tests/test_api.py -v
```

Expected: All tests pass (validation tests pass directly, creation test passes if tmux available).

- [ ] **Step 6: Commit**

```bash
cd ~/coders-war-room
git add server.py tests/test_api.py tests/conftest.py
git commit -m "feat: add agent creation API with validation and tmux lifecycle"
```

---

### Task 3: Reconciliation Scan on Server Boot

**Files:**
- Modify: `~/coders-war-room/server.py`

- [ ] **Step 1: Add the reconciliation function**

Add to `~/coders-war-room/server.py`, after the `agent_status_loop` function, before the FastAPI app section:

```python
def reconcile_tmux_sessions():
    """On boot, discover orphaned warroom-* tmux sessions and adopt them."""
    try:
        result = subprocess.run(
            ["tmux", "list-sessions", "-F", "#{session_name}"],
            capture_output=True, text=True, timeout=5,
        )
        if result.returncode != 0:
            return  # tmux not running or no sessions

        config_names = {a["name"] for a in CONFIG.get("agents", [])}

        for line in result.stdout.strip().split("\n"):
            session_name = line.strip()
            if not session_name.startswith("warroom-"):
                continue
            agent_name = session_name[len("warroom-"):]
            if agent_name in AGENT_NAMES:
                continue  # Already known

            # Orphaned session found — adopt it
            pane_dir = PROJECT_PATH
            try:
                dir_result = subprocess.run(
                    ["tmux", "display-message", "-t", session_name, "-p", "#{pane_current_path}"],
                    capture_output=True, text=True, timeout=2,
                )
                if dir_result.returncode == 0 and dir_result.stdout.strip():
                    pane_dir = dir_result.stdout.strip()
            except (subprocess.TimeoutExpired, FileNotFoundError):
                pass

            agent_entry = {
                "name": agent_name,
                "role": "Dynamic agent (recovered)",
                "tmux_session": session_name,
                "dynamic": True,
            }
            AGENTS.append(agent_entry)
            AGENT_NAMES.add(agent_name)
            AGENT_SESSIONS[agent_name] = session_name
            AGENT_DIRS[agent_name] = pane_dir
            agent_membership[agent_name] = True

    except (subprocess.TimeoutExpired, FileNotFoundError):
        pass  # tmux not available
```

- [ ] **Step 2: Call it in the lifespan function**

Update the `lifespan` function in `server.py`:

```python
@asynccontextmanager
async def lifespan(app: FastAPI):
    await init_db()
    reconcile_tmux_sessions()  # Adopt orphaned sessions on boot
    task1 = asyncio.create_task(flush_queues_loop())
    task2 = asyncio.create_task(agent_status_loop())
    yield
    task1.cancel()
    task2.cancel()
```

- [ ] **Step 3: Run tests**

```bash
cd ~/coders-war-room
python3 -m pytest tests/test_api.py -v
```

Expected: All tests pass.

- [ ] **Step 4: Commit**

```bash
cd ~/coders-war-room
git add server.py
git commit -m "feat: reconcile orphaned tmux sessions on server boot"
```

---

### Task 4: Placeholder startup.md

**Files:**
- Create: `~/coders-war-room/startup.md`

- [ ] **Step 1: Create the placeholder file**

Create `~/coders-war-room/startup.md`:

```markdown
# War Room — Agent Startup Protocol

You are an agent in the Coder's War Room. Follow these rules:

## Communication
- Messages prefixed with `[WARROOM @your-name]` are directed at you. You MUST respond and act.
- Messages prefixed with `[WARROOM]` are broadcasts. Respond only if it impacts your work. Otherwise say "Noted" in the terminal (do NOT post to the war room).
- Messages prefixed with `[WARROOM SYSTEM]` are informational. Do not respond.

## Commands
- Post a message: `~/coders-war-room/warroom.sh post "your message"`
- Direct message: `~/coders-war-room/warroom.sh post --to <agent> "message"`
- See messages for you: `~/coders-war-room/warroom.sh mentions`
- See all messages: `~/coders-war-room/warroom.sh history`

## Git Protocol
All git operations go through the git-agent. Never run destructive git commands (push, reset, rebase) directly. Instead:
1. Post to the war room: `@git-agent please commit my changes in <files>`
2. Wait for git-agent to post a plan
3. Wait for gurvinder or supervisor to confirm
4. git-agent executes

## Conventions
- Keep war room messages concise. This is a chat, not a document.
- When you complete a task or hit a blocker, post it to the war room immediately.
- You have access to all MCP servers and plugins configured in Claude Code.
```

- [ ] **Step 2: Commit**

```bash
cd ~/coders-war-room
git add startup.md
git commit -m "feat: add startup.md agent protocol file"
```

---

### Task 5: Slide-Out Drawer UI

**Files:**
- Modify: `~/coders-war-room/static/index.html`

This is the largest task. The drawer includes: form fields, directory browser, model dropdown, permissions toggle, and the create button with loading state.

- [ ] **Step 1: Add the drawer HTML**

In `~/coders-war-room/static/index.html`, add the drawer markup right after the closing `</div>` of `.main` and before `<script>`:

```html
<!-- Onboarding Drawer -->
<div id="drawer" class="drawer">
  <div class="drawer-header">
    <span class="drawer-title">New Agent</span>
    <button id="drawerClose" class="drawer-x">&times;</button>
  </div>
  <div class="drawer-body">
    <label class="field-label">Agent Name</label>
    <input id="fName" class="field-input" type="text" placeholder="e.g. refactor-agent" maxlength="20" autocomplete="off" spellcheck="false">
    <div class="field-hint">Lowercase, hyphens OK. Becomes the tmux session name.</div>

    <label class="field-label">Working Directory</label>
    <div id="dirPicker" class="dir-picker">
      <div id="dirSelected" class="dir-selected" style="display:none"></div>
      <div id="dirBrowser" class="dir-browser">
        <div id="dirPath" class="dir-path"></div>
        <div id="dirList" class="dir-list"></div>
      </div>
      <button id="dirSelectBtn" class="dir-select-btn">Select this directory</button>
    </div>

    <label class="field-label">Role</label>
    <input id="fRole" class="field-input" type="text" placeholder="What does this agent do?" maxlength="200">

    <label class="field-label">Initial Prompt <span style="color:var(--text-dim)">(optional)</span></label>
    <textarea id="fPrompt" class="field-textarea" rows="4" placeholder="First task or instruction..."></textarea>

    <label class="field-label">Model</label>
    <select id="fModel" class="field-select">
      <option value="opus" selected>Opus 4.6</option>
      <option value="sonnet">Sonnet 4.6</option>
      <option value="haiku">Haiku 4.5</option>
    </select>

    <label class="field-label" style="display:flex;align-items:center;justify-content:space-between">
      Skip Permissions
      <label class="toggle">
        <input id="fPerms" type="checkbox" checked>
        <span class="toggle-slider"></span>
      </label>
    </label>
    <div class="field-hint">On = agent can run tools without asking. Off = prompts for each action.</div>

    <div id="createError" class="create-error" style="display:none"></div>
    <button id="createBtn" class="create-btn">Launch Agent</button>
  </div>
</div>
```

- [ ] **Step 2: Add the drawer CSS**

Add to the `<style>` section, before the closing `</style>`:

```css
/* ═══════════ DRAWER ═══════════ */
.drawer {
  position: fixed;
  top: 0;
  right: -440px;
  width: 420px;
  height: 100vh;
  background: var(--bg-panel);
  border-left: 1px solid var(--border);
  z-index: 100;
  display: flex;
  flex-direction: column;
  transition: right 0.25s cubic-bezier(0.4, 0, 0.2, 1);
  box-shadow: -8px 0 24px rgba(0,0,0,0.4);
}

.drawer.open { right: 0; }

.drawer-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 16px 20px;
  border-bottom: 1px solid var(--border);
}

.drawer-title {
  font-family: 'JetBrains Mono', monospace;
  font-size: 13px;
  font-weight: 600;
  color: var(--green);
  letter-spacing: 1px;
}

.drawer-x {
  background: none;
  border: none;
  color: var(--text-dim);
  font-size: 22px;
  cursor: pointer;
  padding: 0 4px;
  line-height: 1;
}
.drawer-x:hover { color: var(--red); }

.drawer-body {
  flex: 1;
  overflow-y: auto;
  padding: 16px 20px;
}

.field-label {
  font-family: 'JetBrains Mono', monospace;
  font-size: 10px;
  letter-spacing: 1px;
  text-transform: uppercase;
  color: var(--text-secondary);
  margin-top: 14px;
  margin-bottom: 6px;
  display: block;
}

.field-label:first-child { margin-top: 0; }

.field-input, .field-textarea, .field-select {
  width: 100%;
  font-family: 'JetBrains Mono', monospace;
  font-size: 12px;
  background: var(--bg-deep);
  border: 1px solid var(--border);
  color: var(--text-primary);
  padding: 8px 12px;
  border-radius: 4px;
}

.field-input:focus, .field-textarea:focus, .field-select:focus {
  border-color: var(--blue);
  outline: none;
}

.field-textarea { resize: vertical; min-height: 80px; font-family: 'Outfit', sans-serif; }
.field-select { cursor: pointer; }

.field-hint {
  font-size: 10px;
  color: var(--text-dim);
  margin-top: 4px;
}

/* Directory picker */
.dir-picker {
  background: var(--bg-deep);
  border: 1px solid var(--border);
  border-radius: 4px;
  overflow: hidden;
}

.dir-selected {
  padding: 8px 12px;
  font-family: 'JetBrains Mono', monospace;
  font-size: 11px;
  color: var(--green);
  background: var(--green-dim);
  display: flex;
  align-items: center;
  justify-content: space-between;
}

.dir-path {
  padding: 6px 12px;
  font-family: 'JetBrains Mono', monospace;
  font-size: 10px;
  color: var(--text-dim);
  background: var(--bg-card);
  border-bottom: 1px solid var(--border);
  display: flex;
  align-items: center;
  gap: 6px;
}

.dir-up {
  cursor: pointer;
  color: var(--blue);
  font-size: 11px;
}
.dir-up:hover { text-decoration: underline; }

.dir-list {
  max-height: 180px;
  overflow-y: auto;
}

.dir-item {
  padding: 6px 12px;
  font-family: 'JetBrains Mono', monospace;
  font-size: 11px;
  color: var(--text-primary);
  cursor: pointer;
  display: flex;
  align-items: center;
  gap: 6px;
  transition: background 0.1s;
}

.dir-item:hover { background: var(--bg-card-hover); }
.dir-item::before { content: "📁"; font-size: 12px; }

.dir-select-btn {
  width: 100%;
  font-family: 'JetBrains Mono', monospace;
  font-size: 10px;
  padding: 7px;
  background: var(--blue-dim);
  color: var(--blue);
  border: none;
  border-top: 1px solid var(--border);
  cursor: pointer;
  letter-spacing: 0.5px;
}
.dir-select-btn:hover { background: rgba(68,138,255,0.15); }

/* Toggle switch */
.toggle { position: relative; width: 36px; height: 20px; display: inline-block; }
.toggle input { opacity: 0; width: 0; height: 0; }
.toggle-slider {
  position: absolute;
  cursor: pointer;
  inset: 0;
  background: var(--border-bright);
  border-radius: 10px;
  transition: 0.2s;
}
.toggle-slider::before {
  content: "";
  position: absolute;
  height: 14px;
  width: 14px;
  left: 3px;
  bottom: 3px;
  background: var(--text-dim);
  border-radius: 50%;
  transition: 0.2s;
}
.toggle input:checked + .toggle-slider { background: var(--green); }
.toggle input:checked + .toggle-slider::before { transform: translateX(16px); background: var(--bg-void); }

/* Create button */
.create-btn {
  width: 100%;
  font-family: 'JetBrains Mono', monospace;
  font-size: 11px;
  font-weight: 600;
  letter-spacing: 1.5px;
  text-transform: uppercase;
  background: var(--green);
  color: var(--bg-void);
  border: none;
  padding: 12px;
  border-radius: 5px;
  cursor: pointer;
  margin-top: 20px;
  transition: box-shadow 0.15s;
}
.create-btn:hover { box-shadow: 0 0 16px rgba(0,230,118,0.25); }
.create-btn:disabled { background: var(--border); color: var(--text-dim); cursor: wait; box-shadow: none; }

.create-error {
  font-size: 11px;
  color: var(--red);
  background: var(--red-dim);
  padding: 8px 12px;
  border-radius: 4px;
  margin-top: 12px;
}
```

- [ ] **Step 3: Add the "+ New Agent" button to sidebar header**

Update the sidebar header in the HTML:

```html
<div class="sb-head">
  <span class="sb-title">Agents</span>
  <div style="display:flex;gap:6px;align-items:center">
    <span id="agentCount" class="sb-count">0 / 0</span>
    <button id="newAgentBtn" class="abtn abtn-on" style="opacity:1;font-size:10px;padding:3px 10px">+ new</button>
  </div>
</div>
```

- [ ] **Step 4: Add the drawer JavaScript**

Add to the `<script>` section, before the `// Init` block:

```javascript
// ═══════════ Drawer ═══════════
const $drawer = $('drawer');
const $fName = $('fName');
const $fRole = $('fRole');
const $fPrompt = $('fPrompt');
const $fModel = $('fModel');
const $fPerms = $('fPerms');
const $dirBrowser = $('dirBrowser');
const $dirSelected = $('dirSelected');
const $dirPath = $('dirPath');
const $dirList = $('dirList');
const $dirSelectBtn = $('dirSelectBtn');
const $createBtn = $('createBtn');
const $createError = $('createError');

let selectedDir = null;
let currentBrowsePath = null;

$('newAgentBtn').onclick = () => {
  $drawer.classList.add('open');
  resetDrawer();
  browseTo(null);  // Start at home
};

$('drawerClose').onclick = () => $drawer.classList.remove('open');

// Auto-hyphenate name field
$fName.addEventListener('input', () => {
  $fName.value = $fName.value.toLowerCase().replace(/[^a-z0-9-]/g, '-').replace(/--+/g, '-');
});

// Directory browser
async function browseTo(path) {
  const url = path ? `/api/browse?path=${encodeURIComponent(path)}` : '/api/browse?path=~';
  try {
    const resp = await fetch(url);
    if (!resp.ok) { $dirList.innerHTML = '<div class="dir-item" style="color:var(--red)">Cannot access</div>'; return; }
    const data = await resp.json();
    currentBrowsePath = data.current;

    // Show current path with up button
    const parts = data.current.split('/').filter(Boolean);
    const shortPath = parts.length > 3 ? '.../' + parts.slice(-3).join('/') : '/' + parts.join('/');
    $dirPath.innerHTML = `<span class="dir-up" id="dirUp">↑</span> <span>${shortPath}</span>`;
    $('dirUp').onclick = () => browseTo(data.parent);

    // List directories
    $dirList.innerHTML = '';
    if (data.directories.length === 0) {
      $dirList.innerHTML = '<div class="dir-item" style="color:var(--text-dim);cursor:default">No subdirectories</div>';
    } else {
      data.directories.forEach(d => {
        const item = document.createElement('div');
        item.className = 'dir-item';
        item.textContent = d.name;
        item.onclick = () => browseTo(d.path);
        $dirList.appendChild(item);
      });
    }
  } catch (e) {
    $dirList.innerHTML = '<div class="dir-item" style="color:var(--red)">Failed to load</div>';
  }
}

$dirSelectBtn.onclick = () => {
  if (!currentBrowsePath) return;
  selectedDir = currentBrowsePath;
  $dirSelected.style.display = 'flex';
  $dirSelected.innerHTML = `<span>${selectedDir}</span><span style="cursor:pointer;color:var(--text-dim)" onclick="clearDir()">&times;</span>`;
  $dirBrowser.style.display = 'none';
  $dirSelectBtn.style.display = 'none';
};

function clearDir() {
  selectedDir = null;
  $dirSelected.style.display = 'none';
  $dirBrowser.style.display = '';
  $dirSelectBtn.style.display = '';
}

function resetDrawer() {
  $fName.value = '';
  $fRole.value = '';
  $fPrompt.value = '';
  $fModel.value = 'opus';
  $fPerms.checked = true;
  selectedDir = null;
  $dirSelected.style.display = 'none';
  $dirBrowser.style.display = '';
  $dirSelectBtn.style.display = '';
  $createError.style.display = 'none';
  $createBtn.disabled = false;
  $createBtn.textContent = 'Launch Agent';
}

// Create agent
$createBtn.onclick = async () => {
  $createError.style.display = 'none';
  const name = $fName.value.trim();
  const role = $fRole.value.trim();

  if (!name || name.length < 2) { showError('Name is required (min 2 chars)'); return; }
  if (!selectedDir) { showError('Select a working directory'); return; }
  if (!role) { showError('Role is required'); return; }

  $createBtn.disabled = true;
  $createBtn.textContent = 'Creating...';

  try {
    const resp = await fetch('/api/agents/create', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        name,
        directory: selectedDir,
        role,
        initial_prompt: $fPrompt.value,
        model: $fModel.value,
        skip_permissions: $fPerms.checked,
      }),
    });

    const data = await resp.json();
    if (!resp.ok) {
      showError(data.error || 'Failed to create agent');
      $createBtn.disabled = false;
      $createBtn.textContent = 'Launch Agent';
      return;
    }

    // Success — add to roster, close drawer
    agentRoster.push({ name: data.agent.name, role, dynamic: true });
    agentData[data.agent.name] = {
      presence: data.agent.presence || 'active',
      activity: null,
      in_room: true,
    };
    renderAgents();
    $drawer.classList.remove('open');

  } catch (e) {
    showError('Network error — is the server running?');
    $createBtn.disabled = false;
    $createBtn.textContent = 'Launch Agent';
  }
};

function showError(msg) {
  $createError.textContent = msg;
  $createError.style.display = 'block';
}
```

- [ ] **Step 5: Handle the `agent_created` WebSocket event**

In the WebSocket `onmessage` handler, add a case for `agent_created`:

```javascript
} else if (d.type === 'agent_created') {
  // Another client created an agent — add to our roster
  const a = d.agent;
  if (!agentRoster.find(r => r.name === a.name)) {
    agentRoster.push({ name: a.name, role: a.role, dynamic: a.dynamic });
    agentData[a.name] = { presence: a.presence, activity: a.activity, in_room: a.in_room };
    renderAgents();
  }
}
```

- [ ] **Step 6: Add `~` indicator for dynamic agents in renderAgents()**

In the `renderAgents` function, where the agent name is rendered, check for `dynamic`:

```javascript
const isDynamic = a.dynamic || false;
// In the name span:
`<span class="ac-name" style="color:${color(a.name)}">${a.name}${isDynamic ? ' <span style="font-size:9px;color:var(--text-dim);font-weight:400">~</span>' : ''}</span>`
```

- [ ] **Step 7: Test the drawer manually**

```bash
cd ~/coders-war-room
pkill -f "python3.*server.py"; sleep 1
python3 server.py &
sleep 2
open http://localhost:5680
```

Test flow:
1. Click "+ new" in sidebar header
2. Drawer slides in from right
3. Type agent name, browse to a directory, fill in role
4. Click "Launch Agent"
5. Agent appears in sidebar with `~` indicator
6. System message appears in chat

- [ ] **Step 8: Commit**

```bash
cd ~/coders-war-room
git add static/index.html
git commit -m "feat: add slide-out drawer for web-based agent onboarding"
```

---

### Task 6: Full Integration Test

**Files:**
- Modify: `~/coders-war-room/tests/test_integration.py`

- [ ] **Step 1: Add integration test for the full flow**

Add to `~/coders-war-room/tests/test_integration.py`:

```python
def test_browse_api():
    """Test the directory browse endpoint."""
    import os
    home = os.path.expanduser("~")
    resp = httpx.get(f"{SERVER_URL}/api/browse?path={home}")
    assert resp.status_code == 200
    data = resp.json()
    assert data["current"] == home
    assert len(data["directories"]) > 0
    # Security: browsing outside home should fail
    resp = httpx.get(f"{SERVER_URL}/api/browse?path=/etc")
    assert resp.status_code == 403


def test_create_and_use_dynamic_agent():
    """Test creating a dynamic agent via API and verifying it joins the roster."""
    import os
    resp = httpx.post(f"{SERVER_URL}/api/agents/create", json={
        "name": "integration-test-agent",
        "directory": os.path.expanduser("~"),
        "role": "Integration test",
        "initial_prompt": "",
        "model": "opus",
        "skip_permissions": True,
    })
    assert resp.status_code == 200
    data = resp.json()
    assert data["status"] == "created"
    assert data["agent"]["name"] == "integration-test-agent"

    # Verify it shows up in the agent list
    resp = httpx.get(f"{SERVER_URL}/api/agents")
    agents = resp.json()
    names = [a["name"] for a in agents]
    assert "integration-test-agent" in names

    # Clean up: kill the tmux session
    subprocess.run(["tmux", "kill-session", "-t", "warroom-integration-test-agent"], capture_output=True)
```

- [ ] **Step 2: Run integration tests**

```bash
cd ~/coders-war-room
python3 -m pytest tests/test_integration.py -v -s
```

- [ ] **Step 3: Commit**

```bash
cd ~/coders-war-room
git add tests/test_integration.py
git commit -m "test: add integration tests for browse API and dynamic agent creation"
```
