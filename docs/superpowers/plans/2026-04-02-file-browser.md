# File Browser Right Panel Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a right-side file browser panel with project directory tree, agent ownership dots, click-to-open-in-Warp, and drag-and-drop to chat/agent cards.

**Architecture:** New `GET /api/files` endpoint returns directory listings with ownership info. `POST /api/files/open` opens files in Warp. Frontend renders a lazy-loaded tree with drag-and-drop via HTML5 API. Three-column layout: agents | chat | files.

**Tech Stack:** Python 3.12 (fnmatch for ownership matching), FastAPI, vanilla JS (HTML5 Drag and Drop API)

**Design Spec:** `docs/superpowers/specs/2026-04-02-file-browser-design.md`

---

## File Structure

| File | Action | Responsibility |
|------|--------|---------------|
| `server.py` | Modify | `GET /api/files`, `POST /api/files/open`, ownership-per-file resolution, dir_has_owned precomputation |
| `static/index.html` | Modify | Three-column layout, file tree panel, drag-and-drop handlers |
| `tests/test_api.py` | Modify | Tests for files API |

---

### Task 1: Server — Files API and Ownership Resolution

**Files:**
- Modify: `~/coders-war-room/server.py`
- Modify: `~/coders-war-room/tests/test_api.py`

- [ ] **Step 1: Write failing tests**

Add to `~/coders-war-room/tests/test_api.py`:

```python
@pytest.mark.asyncio
async def test_list_files_root():
    from server import app
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        resp = await client.get("/api/files?path=.")
        assert resp.status_code == 200
        data = resp.json()
        assert "current" in data
        assert "entries" in data
        assert isinstance(data["entries"], list)
        # Should have directories and files
        types = {e["type"] for e in data["entries"]}
        assert "dir" in types or "file" in types
        # Each entry has required fields
        for e in data["entries"]:
            assert "name" in e
            assert "type" in e
            assert "path" in e


@pytest.mark.asyncio
async def test_list_files_with_ownership():
    from server import app
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        resp = await client.get("/api/files?path=northstar")
        assert resp.status_code == 200
        data = resp.json()
        # northstar/ should have files owned by various agents
        owned = [e for e in data["entries"] if e.get("owner")]
        # At least some files should be owned (state.py, config.py, etc.)
        assert len(owned) > 0
        # Owned files should have a color
        for e in owned:
            assert e["color"] is not None


@pytest.mark.asyncio
async def test_list_files_security():
    from server import app
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        resp = await client.get("/api/files?path=../../etc")
        assert resp.status_code == 403


@pytest.mark.asyncio
async def test_list_files_dirs_have_owned():
    from server import app
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        resp = await client.get("/api/files?path=.")
        assert resp.status_code == 200
        data = resp.json()
        dirs = [e for e in data["entries"] if e["type"] == "dir"]
        # northstar dir should have has_owned = True
        northstar = [d for d in dirs if d["name"] == "northstar"]
        if northstar:
            assert northstar[0]["has_owned"] is True
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd ~/coders-war-room
python3 -m pytest tests/test_api.py::test_list_files_root tests/test_api.py::test_list_files_with_ownership tests/test_api.py::test_list_files_security tests/test_api.py::test_list_files_dirs_have_owned -v
```

Expected: FAIL — no `/api/files` route

- [ ] **Step 3: Add ownership-per-file helpers**

Add to `server.py` after the `resolve_ownership()` function:

```python
import fnmatch

# Pre-computed: which directories contain owned files (for has_owned flag)
dir_has_owned: dict[str, bool] = {}


def precompute_dir_ownership():
    """Pre-compute which directories contain owned files."""
    dir_has_owned.clear()
    for agent in AGENTS:
        for pattern in agent.get("owns", []):
            full = str(Path(PROJECT_PATH) / pattern)
            matches = globmod.glob(full, recursive=True)
            for match in matches:
                if not Path(match).is_file():
                    continue
                # Mark all ancestor directories as having owned files
                rel = str(Path(match).relative_to(PROJECT_PATH))
                parts = Path(rel).parts
                for i in range(len(parts) - 1):
                    dir_path = str(Path(*parts[:i + 1]))
                    dir_has_owned[dir_path] = True


def get_file_owner(relative_path: str) -> tuple[Optional[str], Optional[str]]:
    """Check which agent owns a file. Returns (agent_name, color) or (None, None)."""
    for agent in AGENTS:
        for pattern in agent.get("owns", []):
            if fnmatch.fnmatch(relative_path, pattern):
                return agent["name"], COLORS.get(agent["name"])
    return None, None
```

Also add the COLORS dict near the top of server.py (after AGENTS):

```python
COLORS = {
    'gurvinder': '#ff9100',
    'supervisor': '#b388ff',
    'phase-1': '#448aff',
    'phase-2': '#00e676',
    'phase-3': '#ff80ab',
    'phase-4': '#18ffff',
    'phase-5': '#ea80fc',
    'phase-6': '#69f0ae',
    'git-agent': '#ffd740',
}
```

- [ ] **Step 4: Add the files API endpoint**

Add before the `/api/agents/{agent_name}/status` endpoint:

```python
@app.get("/api/files")
async def list_files(path: str = "."):
    """List directory contents with ownership info for the file browser."""
    # Resolve relative to project
    target = (Path(PROJECT_PATH) / path).resolve()
    project_resolved = Path(PROJECT_PATH).resolve()

    # Security: must be under project directory
    if not str(target).startswith(str(project_resolved)):
        return JSONResponse({"error": "Path must be under project directory"}, status_code=403)

    if not target.is_dir():
        return JSONResponse({"error": f"Not a directory: {path}"}, status_code=404)

    parent_rel = str(target.parent.relative_to(project_resolved)) if target != project_resolved else None

    entries = []
    try:
        items = sorted(target.iterdir(), key=lambda p: (not p.is_dir(), p.name.lower()))
        for item in items:
            name = item.name
            # Skip hidden except .claude
            if name.startswith(".") and name != ".claude":
                continue

            rel_path = str(item.relative_to(project_resolved))

            if item.is_dir():
                entries.append({
                    "name": name,
                    "type": "dir",
                    "path": rel_path,
                    "has_owned": dir_has_owned.get(rel_path, False),
                })
            elif item.is_file():
                owner, color = get_file_owner(rel_path)
                entries.append({
                    "name": name,
                    "type": "file",
                    "path": rel_path,
                    "owner": owner,
                    "color": color,
                })
    except PermissionError:
        return JSONResponse({"error": "Permission denied"}, status_code=403)

    return {
        "current": str(target.relative_to(project_resolved)),
        "parent": parent_rel,
        "entries": entries,
    }
```

- [ ] **Step 5: Add the file open endpoint**

Add after the `/api/files` endpoint:

```python
@app.post("/api/files/open")
async def open_file(data: dict):
    """Open a file in Warp with syntax highlighting."""
    file_path = data.get("path", "")
    full_path = (Path(PROJECT_PATH) / file_path).resolve()
    project_resolved = Path(PROJECT_PATH).resolve()

    if not str(full_path).startswith(str(project_resolved)):
        return JSONResponse({"error": "Path must be under project directory"}, status_code=403)
    if not full_path.is_file():
        return JSONResponse({"error": "File not found"}, status_code=404)

    try:
        launcher = Path(f"/tmp/warroom-view-{full_path.stem}.sh")
        launcher.write_text(
            f"#!/bin/bash\n"
            f"cd {PROJECT_PATH}\n"
            f"bat --paging=always '{full_path}' 2>/dev/null || less '{full_path}'\n"
        )
        launcher.chmod(0o755)

        warp = Path("/Applications/Warp.app")
        if warp.exists():
            subprocess.run(["open", "-a", "Warp", str(launcher)], capture_output=True, timeout=5)
        else:
            subprocess.run(
                ["osascript", "-e",
                 f'tell application "Terminal"\n  activate\n  do script "bat --paging=always \'{full_path}\' 2>/dev/null || less \'{full_path}\'"\nend tell'],
                capture_output=True, timeout=5,
            )
        return {"status": "opened", "path": file_path}
    except Exception as e:
        return JSONResponse({"error": str(e)}, status_code=500)
```

- [ ] **Step 6: Call precompute_dir_ownership() in lifespan**

Update the `lifespan` function to call it after `resolve_ownership()`:

```python
    resolve_ownership()
    precompute_dir_ownership()
    refresh_last_commits()
```

- [ ] **Step 7: Update conftest to patch new globals**

Add to the `_init_db` fixture in `tests/conftest.py`:

```python
    monkeypatch.setattr(server, "dir_has_owned", {})
```

- [ ] **Step 8: Run all tests**

```bash
cd ~/coders-war-room
python3 -m pytest tests/test_api.py -v
```

Expected: All tests pass (16 existing + 4 new = 20).

- [ ] **Step 9: Commit**

```bash
cd ~/coders-war-room
git add server.py tests/test_api.py tests/conftest.py
git commit -m "feat: add files API with ownership resolution and Warp open"
```

---

### Task 2: Frontend — Three-Column Layout and File Tree Panel

**Files:**
- Modify: `~/coders-war-room/static/index.html`

This task adds the right panel with the file tree. No drag-and-drop yet — that's Task 3.

- [ ] **Step 1: Update the HTML layout to three columns**

Find the `.main` div and add the file panel:

```html
<div class="main">
  <aside class="sidebar">
    <!-- existing agent list -->
  </aside>

  <div class="chat">
    <!-- existing chat -->
  </div>

  <aside class="file-panel" id="filePanel">
    <div class="fp-head">
      <span class="fp-title">Files</span>
      <span id="fpPath" class="fp-path"></span>
    </div>
    <div id="fileTree" class="fp-tree"></div>
  </aside>
</div>
```

- [ ] **Step 2: Add the file panel CSS**

```css
/* ═══════════ FILE PANEL ═══════════ */
.file-panel {
  width: 280px;
  background: var(--bg-deep);
  border-left: 1px solid var(--border);
  display: flex;
  flex-direction: column;
  flex-shrink: 0;
  overflow: hidden;
}

.fp-head {
  padding: 12px 14px 8px;
  border-bottom: 1px solid var(--border);
  display: flex;
  align-items: center;
  gap: 8px;
}

.fp-title {
  font-family: 'JetBrains Mono', monospace;
  font-size: 9px;
  letter-spacing: 2.5px;
  text-transform: uppercase;
  color: var(--text-dim);
}

.fp-path {
  font-family: 'JetBrains Mono', monospace;
  font-size: 9px;
  color: var(--text-dim);
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.fp-tree {
  flex: 1;
  overflow-y: auto;
  padding: 6px 0;
}

.fp-item {
  display: flex;
  align-items: center;
  gap: 5px;
  padding: 3px 10px;
  cursor: pointer;
  font-family: 'JetBrains Mono', monospace;
  font-size: 11px;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
  transition: background 0.1s;
  user-select: none;
}

.fp-item:hover { background: var(--bg-card-hover); }

.fp-item.dir { color: var(--text-secondary); }
.fp-item.file { color: var(--text-dim); }
.fp-item.file.owned { color: var(--text-secondary); }

.fp-arrow {
  font-size: 8px;
  width: 10px;
  text-align: center;
  color: var(--text-dim);
  flex-shrink: 0;
}

.fp-dot {
  width: 6px;
  height: 6px;
  border-radius: 50%;
  flex-shrink: 0;
}

.fp-name {
  overflow: hidden;
  text-overflow: ellipsis;
}

/* Nesting indentation */
.fp-item[data-depth="0"] { padding-left: 10px; }
.fp-item[data-depth="1"] { padding-left: 26px; }
.fp-item[data-depth="2"] { padding-left: 42px; }
.fp-item[data-depth="3"] { padding-left: 58px; }
.fp-item[data-depth="4"] { padding-left: 74px; }

/* Drag states */
.fp-item.dragging { opacity: 0.5; }
```

- [ ] **Step 3: Add the file tree JavaScript**

Add to the `<script>` section, before the `// Init` block:

```javascript
// ═══════════ File Browser ═══════════
const $fileTree = $('fileTree');
const $fpPath = $('fpPath');
const fileTreeState = {}; // path -> {expanded: bool, entries: [...]}

async function loadDir(path, depth, parentEl, autoExpand) {
  try {
    const resp = await fetch(`/api/files?path=${encodeURIComponent(path)}`);
    if (!resp.ok) return;
    const data = await resp.json();

    if (depth === 0) {
      $fpPath.textContent = data.current === '.' ? 'project root' : data.current;
    }

    data.entries.forEach(entry => {
      const item = document.createElement('div');
      item.dataset.depth = depth;
      item.dataset.path = entry.path;
      item.dataset.type = entry.type;

      if (entry.type === 'dir') {
        item.className = 'fp-item dir';
        const isExpanded = autoExpand && entry.has_owned;
        item.innerHTML = `
          <span class="fp-arrow">${isExpanded ? '▾' : '▸'}</span>
          <span class="fp-name">${esc(entry.name)}</span>
        `;
        parentEl.appendChild(item);

        // Container for children
        const children = document.createElement('div');
        children.style.display = isExpanded ? '' : 'none';
        children.dataset.dirPath = entry.path;
        parentEl.appendChild(children);

        if (isExpanded) {
          loadDir(entry.path, depth + 1, children, true);
        }

        item.onclick = (e) => {
          e.stopPropagation();
          const arrow = item.querySelector('.fp-arrow');
          if (children.style.display === 'none') {
            children.style.display = '';
            arrow.textContent = '▾';
            if (!children.hasChildNodes()) {
              loadDir(entry.path, depth + 1, children, false);
            }
          } else {
            children.style.display = 'none';
            arrow.textContent = '▸';
          }
        };

      } else {
        // File
        const isOwned = !!entry.owner;
        item.className = `fp-item file${isOwned ? ' owned' : ''}`;
        item.draggable = true;
        const dot = entry.color
          ? `<span class="fp-dot" style="background:${entry.color};box-shadow:0 0 4px ${entry.color}44" title="${esc(entry.owner)}"></span>`
          : '<span style="width:6px"></span>';
        item.innerHTML = `${dot}<span class="fp-name">${esc(entry.name)}</span>`;

        // Click → open in Warp
        item.onclick = (e) => {
          e.stopPropagation();
          fetch('/api/files/open', {
            method: 'POST',
            headers: {'Content-Type': 'application/json'},
            body: JSON.stringify({path: entry.path}),
          });
        };

        // Drag start
        item.ondragstart = (e) => {
          e.dataTransfer.setData('text/plain', entry.path);
          e.dataTransfer.setData('application/x-warroom-file', entry.path);
          item.classList.add('dragging');
        };
        item.ondragend = () => item.classList.remove('dragging');

        parentEl.appendChild(item);
      }
    });
  } catch (e) {
    console.error('File tree load error:', e);
  }
}

// Load root on init
function initFileTree() {
  $fileTree.innerHTML = '';
  loadDir('.', 0, $fileTree, true);
}
```

- [ ] **Step 4: Call initFileTree() in the init block**

At the end of the `// Init` section:

```javascript
initFileTree();
```

- [ ] **Step 5: Test manually**

```bash
cd ~/coders-war-room
pkill -f "python3.*server.py"; sleep 1
python3 server.py &
sleep 2
open http://localhost:5680
```

Verify:
1. Three-column layout visible
2. File tree shows project root with folders and files
3. Owned files have colored dots
4. northstar/ auto-expanded (has owned files)
5. Click a file → opens in Warp
6. Folders expand/collapse on click

- [ ] **Step 6: Commit**

```bash
cd ~/coders-war-room
git add static/index.html
git commit -m "feat: add file browser right panel with tree view and ownership dots"
```

---

### Task 3: Frontend — Drag and Drop

**Files:**
- Modify: `~/coders-war-room/static/index.html`

- [ ] **Step 1: Add drop zone CSS**

```css
/* ─── Drop zones ─── */
.msg-input.drop-active {
  border-color: var(--blue);
  box-shadow: 0 0 12px rgba(68,138,255,0.2);
}

.ac.drop-active {
  border-color: var(--green);
  box-shadow: 0 0 12px rgba(0,230,118,0.2);
}
```

- [ ] **Step 2: Add drop handler for chat input**

In the JavaScript, after the file tree code:

```javascript
// ═══════════ Drag & Drop: File → Chat Input ═══════════
$input.addEventListener('dragover', (e) => {
  if (e.dataTransfer.types.includes('application/x-warroom-file')) {
    e.preventDefault();
    $input.classList.add('drop-active');
  }
});

$input.addEventListener('dragleave', () => {
  $input.classList.remove('drop-active');
});

$input.addEventListener('drop', (e) => {
  e.preventDefault();
  $input.classList.remove('drop-active');
  const filePath = e.dataTransfer.getData('application/x-warroom-file');
  if (filePath) {
    // Insert at cursor position or append
    const start = $input.selectionStart;
    const before = $input.value.slice(0, start);
    const after = $input.value.slice(start);
    $input.value = before + filePath + ' ' + after;
    $input.focus();
    $input.selectionStart = $input.selectionEnd = start + filePath.length + 1;
  }
});
```

- [ ] **Step 3: Add drop handler for agent cards**

In the `renderAgents()` function, after the button click handlers for each active agent card, add drag-and-drop handlers:

```javascript
    // Drop zone: file → agent card
    card.addEventListener('dragover', (e) => {
      if (e.dataTransfer.types.includes('application/x-warroom-file')) {
        e.preventDefault();
        card.classList.add('drop-active');
      }
    });

    card.addEventListener('dragleave', () => {
      card.classList.remove('drop-active');
    });

    card.addEventListener('drop', (e) => {
      e.preventDefault();
      card.classList.remove('drop-active');
      const filePath = e.dataTransfer.getData('application/x-warroom-file');
      if (filePath) {
        $target.value = a.name;
        $input.value = `[file: ${filePath}] `;
        $input.focus();
      }
    });
```

This needs to be added inside the `activeAgents.forEach(a => { ... })` block, after the button handlers and before `$agents.appendChild(card)`.

- [ ] **Step 4: Test manually**

1. Drag a file from the tree to the chat input → path appears in input
2. Drag a file to an agent card → @target set, `[file: path]` inserted, input focused
3. Type an instruction and send → message delivered with file reference

- [ ] **Step 5: Commit**

```bash
cd ~/coders-war-room
git add static/index.html
git commit -m "feat: add drag-and-drop from file tree to chat and agent cards"
```

---

### Task 4: Integration Tests

**Files:**
- Modify: `~/coders-war-room/tests/test_integration.py`

- [ ] **Step 1: Add integration tests**

```python
def test_files_api():
    """Test the files listing endpoint."""
    resp = httpx.get(f"{SERVER_URL}/api/files?path=.")
    assert resp.status_code == 200
    data = resp.json()
    assert "entries" in data
    assert len(data["entries"]) > 0
    # Check northstar dir exists and has owned files
    dirs = [e for e in data["entries"] if e["type"] == "dir" and e["name"] == "northstar"]
    assert len(dirs) == 1
    assert dirs[0]["has_owned"] is True


def test_files_ownership():
    """Test that files show correct ownership."""
    resp = httpx.get(f"{SERVER_URL}/api/files?path=northstar")
    assert resp.status_code == 200
    data = resp.json()
    # state.py should be owned by phase-1
    state = [e for e in data["entries"] if e["name"] == "state.py"]
    if state:
        assert state[0]["owner"] == "phase-1"
        assert state[0]["color"] is not None


def test_files_security():
    """Test path traversal prevention."""
    resp = httpx.get(f"{SERVER_URL}/api/files?path=../../etc")
    assert resp.status_code == 403
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
git commit -m "test: add integration tests for file browser API"
```
