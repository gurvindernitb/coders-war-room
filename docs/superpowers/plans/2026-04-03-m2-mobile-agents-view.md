# M2: Mobile Agents View + Identity System — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a color + avatar identity system with role-based defaults and user overrides, then redesign the mobile agents tab with elongated rounded cards featuring circular avatars.

**Architecture:** Backend first (SQLite schema + API), then frontend identity system (JS icon library + color resolution), then desktop additive changes (avatar in sidebar + picker in creation form), then mobile agents redesign (CSS + JS). All mobile CSS inside `@media (max-width: 767px)`. Desktop layout enhanced additively, never replaced.

**Tech Stack:** Python/FastAPI (server.py), SQLite (agents table), Vanilla CSS + JavaScript (index.html), Phosphor duotone SVGs (embedded inline).

---

## File Map

| File | Action | What changes |
|------|--------|-------------|
| `server.py` | Modify | Add `color`/`icon` columns, update `persist_agent`, update API endpoints, add PATCH endpoint |
| `static/index.html` | Modify | Add `AVATAR_ICONS` library, color/icon resolution, desktop avatar circles, creation form pickers, mobile agent card redesign |

---

### Task 1: SQLite Schema + Server API Changes

**Files:**
- Modify: `server.py` — schema, persist_agent, list_agents, create agent, new PATCH endpoint

This task adds `color` and `icon` columns to the agents table, updates all agent persistence and API endpoints.

- [ ] **Step 1: Add color and icon columns to SQLite schema**

In `init_db()`, after the existing `CREATE TABLE IF NOT EXISTS agents` block (line ~194), add ALTER TABLE statements to add the new columns. These are safe to run repeatedly — they'll fail silently if columns already exist.

Find the line:
```python
        await db.commit()


async def persist_agent(agent_entry: dict, directory: str = "", model: str = "opus", skip_permissions: bool = True):
```

Insert BEFORE `await db.commit()`:
```python
        # Add color/icon columns if they don't exist (safe migration)
        try:
            await db.execute("ALTER TABLE agents ADD COLUMN color TEXT")
        except Exception:
            pass  # Column already exists
        try:
            await db.execute("ALTER TABLE agents ADD COLUMN icon TEXT")
        except Exception:
            pass  # Column already exists
```

- [ ] **Step 2: Update persist_agent to accept color and icon**

Replace the entire `persist_agent` function with:

```python
async def persist_agent(agent_entry: dict, directory: str = "", model: str = "opus", skip_permissions: bool = True, color: str = None, icon: str = None):
    """Save or update an agent in SQLite. Called on create and reconcile."""
    async with aiosqlite.connect(DB_PATH) as db:
        await db.execute("""
            INSERT INTO agents (name, role, instructions, role_type, tmux_session, directory, model, skip_permissions, dynamic, active, color, icon)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 1, ?, ?)
            ON CONFLICT(name) DO UPDATE SET
                role = excluded.role,
                tmux_session = excluded.tmux_session,
                directory = excluded.directory,
                model = excluded.model,
                active = 1,
                color = COALESCE(excluded.color, agents.color),
                icon = COALESCE(excluded.icon, agents.icon)
        """, (
            agent_entry["name"],
            agent_entry.get("role", ""),
            agent_entry.get("instructions", ""),
            agent_entry.get("role_type", agent_entry["name"]),
            agent_entry["tmux_session"],
            directory,
            model,
            1 if skip_permissions else 0,
            1 if agent_entry.get("dynamic", True) else 0,
            color,
            icon,
        ))
        await db.commit()
```

- [ ] **Step 3: Update load_persisted_agents to read color and icon**

In the `load_persisted_agents()` function, the agent_entry dict and agent_config dict need to include color and icon. Find where `agent_entry` is built inside the function and add the fields:

Find:
```python
        agent_entry = {
            "name": name,
            "role": row["role"],
            "instructions": row["instructions"],
            "role_type": row["role_type"],
            "tmux_session": session,
            "dynamic": bool(row["dynamic"]),
        }
```

Replace with:
```python
        agent_entry = {
            "name": name,
            "role": row["role"],
            "instructions": row["instructions"],
            "role_type": row["role_type"],
            "tmux_session": session,
            "dynamic": bool(row["dynamic"]),
            "color": row["color"] if "color" in row.keys() else None,
            "icon": row["icon"] if "icon" in row.keys() else None,
        }
```

- [ ] **Step 4: Update list_agents API to include color and icon**

Find the `list_agents()` function (line ~800). Update the return dict to include color and icon:

Find:
```python
            "dynamic": a.get("dynamic", False),
        }
        for a in AGENTS
```

Replace with:
```python
            "dynamic": a.get("dynamic", False),
            "color": a.get("color"),
            "icon": a.get("icon"),
        }
        for a in AGENTS
```

- [ ] **Step 5: Update AgentCreate model to accept color and icon**

Find:
```python
class AgentCreate(BaseModel):
    name: str
    directory: str
    role: str
    initial_prompt: str = ""
    model: str = "opus"
    skip_permissions: bool = True
    instructions: str = ""
    role_type: str = ""
```

Replace with:
```python
class AgentCreate(BaseModel):
    name: str
    directory: str
    role: str
    initial_prompt: str = ""
    model: str = "opus"
    skip_permissions: bool = True
    instructions: str = ""
    role_type: str = ""
    color: Optional[str] = None
    icon: Optional[str] = None
```

- [ ] **Step 6: Update create agent to persist color and icon**

Find where `persist_agent` is called in the create agent endpoint:
```python
        await persist_agent(agent_entry, agent_dir, req.model, req.skip_permissions)
```

Replace with:
```python
        await persist_agent(agent_entry, agent_dir, req.model, req.skip_permissions, req.color, req.icon)
```

Also add color and icon to the agent_entry dict. Find:
```python
        agent_entry = {
            "name": req.name,
            "role": req.role,
            "instructions": req.instructions,
            "role_type": req.role_type or req.name,
            "tmux_session": session,
            "dynamic": True,
        }
```

Replace with:
```python
        agent_entry = {
            "name": req.name,
            "role": req.role,
            "instructions": req.instructions,
            "role_type": req.role_type or req.name,
            "tmux_session": session,
            "dynamic": True,
            "color": req.color,
            "icon": req.icon,
        }
```

- [ ] **Step 7: Add PATCH endpoint for updating agent color/icon**

Add after the `list_agents` endpoint (after line ~815):

```python
class AgentIdentityUpdate(BaseModel):
    color: Optional[str] = None
    icon: Optional[str] = None


@app.patch("/api/agents/{agent_name}")
async def update_agent_identity(agent_name: str, req: AgentIdentityUpdate):
    """Update an agent's color and/or icon."""
    if agent_name not in AGENT_NAMES:
        return JSONResponse({"error": f"Agent '{agent_name}' not found"}, status_code=404)
    # Update in-memory
    for a in AGENTS:
        if a["name"] == agent_name:
            if req.color is not None:
                a["color"] = req.color
            if req.icon is not None:
                a["icon"] = req.icon
            break
    # Persist to SQLite
    async with aiosqlite.connect(DB_PATH) as db:
        if req.color is not None:
            await db.execute("UPDATE agents SET color = ? WHERE name = ?", (req.color, agent_name))
        if req.icon is not None:
            await db.execute("UPDATE agents SET icon = ? WHERE name = ?", (req.icon, agent_name))
        await db.commit()
    return {"status": "updated", "name": agent_name, "color": req.color, "icon": req.icon}
```

- [ ] **Step 8: Update the color function on the server side**

The `get_agent_color()` function needs to check the agent's stored color first. Replace:

```python
def get_agent_color(name: str) -> str:
    """Get color for an agent — static map for known agents, palette for dynamic ones."""
    if name in COLORS:
        return COLORS[name]
    # Assign a deterministic color from palette based on name hash
    idx = hash(name) % len(COLOR_PALETTE)
    color = COLOR_PALETTE[idx]
    COLORS[name] = color  # Cache it
    return color
```

With:

```python
# Role-based color defaults
ROLE_COLOR_DEFAULTS = {
    'supervisor': '#b388ff', 'lead': '#b388ff', 'director': '#b388ff',
    'engineer': '#448aff', 'builder': '#448aff', 'developer': '#448aff', 'coder': '#448aff', 'dev': '#448aff',
    'scout': '#18ffff', 'researcher': '#18ffff', 'investigator': '#18ffff',
    'qa': '#ff5252', 'q-a': '#ff5252', 'quality': '#ff5252', 'tester': '#ff5252', 'validator': '#ff5252',
    'git': '#ffd740', 'git-agent': '#ffd740', 'vcs': '#ffd740',
    'chronicler': '#ff80ab', 'observer': '#ff80ab', 'logger': '#ff80ab',
    'gurvinder': '#ff9100',
}
EXTRA_SWATCHES = ['#64ffda', '#b9f6ca', '#ff6e40', '#8c9eff', '#ffcc80', '#84ffff', '#f48fb1', '#ce93d8']


def get_agent_color(name: str) -> str:
    """Get color for an agent. Priority: stored color > role default > hash-based."""
    # 1. Check in-memory agent entry for stored color
    for a in AGENTS:
        if a["name"] == name and a.get("color"):
            return a["color"]
    # 2. Check static map (backward compat)
    if name in COLORS:
        return COLORS[name]
    # 3. Role keyword match
    name_lower = name.lower()
    for keyword, c in ROLE_COLOR_DEFAULTS.items():
        if keyword in name_lower:
            COLORS[name] = c
            return c
    # 4. Hash-based fallback from extra swatches
    idx = hash(name) % len(EXTRA_SWATCHES)
    c = EXTRA_SWATCHES[idx]
    COLORS[name] = c
    return c
```

- [ ] **Step 9: Restart and verify API**

```bash
cd ~/coders-war-room
bash restart-server.sh
curl -s http://localhost:5680/api/agents | python3 -c "import sys,json; [print(f'{a[\"name\"]:15s} color={a.get(\"color\",\"None\"):10s} icon={a.get(\"icon\",\"None\")}') for a in json.load(sys.stdin)]"
```

Expected: 9 agents, all with `color=None icon=None` (no overrides set yet).

- [ ] **Step 10: Commit**

```bash
git add server.py
git commit -m "feat(m2): step 1 — agent identity schema, API, color resolution"
```

---

### Task 2: Phosphor Duotone Icon Library (JavaScript)

**Files:**
- Modify: `static/index.html` — JavaScript section

This task embeds the 25 Phosphor duotone SVG icons as a JavaScript object and adds role-based icon resolution.

- [ ] **Step 1: Fetch Phosphor duotone SVG paths**

Go to https://phosphoricons.com and get the duotone SVG paths for all 25 icons. Each icon needs the full SVG inner content (path elements).

Create the `AVATAR_ICONS` object. Insert it in the JavaScript section BEFORE the `SVG_ICONS` object (which already exists for tab bar/bottom sheet icons).

```javascript
// ═══════════ Phosphor Duotone Avatar Icons ═══════════
const AVATAR_ICONS = {
  'crown': '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" fill="currentColor"><path d="M216,56l-24,96H64L40,56l50.47,37.6a8,8,0,0,0,11-2.23L128,48l26.53,43.37a8,8,0,0,0,11,2.23Z" opacity="0.2"/><path d="M248,80a28,28,0,1,0-51.12,15.77l-26.79,33L146,73.4a28,28,0,1,0-36,0L85.91,128.74l-26.79-33a28,28,0,1,0-26.6,12L48,200a16,16,0,0,0,16,16H192a16,16,0,0,0,16-16l15.49-92.21A28,28,0,0,0,248,80ZM128,40a12,12,0,1,1-12,12A12,12,0,0,1,128,40ZM24,80A12,12,0,1,1,36,92,12,12,0,0,1,24,80Zm196,12a12,12,0,1,1,12-12A12,12,0,0,1,220,92ZM192,200H64l-14-83.44L78.84,152.3a8,8,0,0,0,6.27,3h0a8,8,0,0,0,6.2-3L128,101.07l36.69,51.24a8,8,0,0,0,6.2,3h0a8,8,0,0,0,6.27-3L206,116.56Z"/></svg>',
  'wrench': '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" fill="currentColor"><path d="M217,169,167.6,119.6a68,68,0,0,0-31.2-87.6l48.8,48.8L169,97,152.8,80.8l16.2-16.2L120.2,15.8a68,68,0,0,0,87.6,31.2L257,96.4Z" opacity="0.2"/><path d="M226.76,69a8,8,0,0,0-12.84-2.88l-40.3,37.19-17.23-3.7-3.7-17.23,37.19-40.3A8,8,0,0,0,187,29.24,72.08,72.08,0,0,0,79.79,90.34L37.66,132.46a31.82,31.82,0,0,0,0,45L85.54,222.34a31.82,31.82,0,0,0,45,0l42.12-42.13A72.08,72.08,0,0,0,226.76,69ZM119.18,211,86.88,178.66,160,105.54l-9.23-9.23A56,56,0,0,1,212.92,56.4L178.5,93.87l5.59,26,26,5.59,37.47-34.42A56,56,0,0,1,207.65,153.2l-9.23-9.23Z"/></svg>',
  'magnifying-glass': '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" fill="currentColor"><circle cx="112" cy="112" r="72" opacity="0.2"/><path d="M229.66,218.34l-50.07-50.07a88.11,88.11,0,1,0-11.31,11.31l50.07,50.07a8,8,0,0,0,11.31-11.31ZM40,112a72,72,0,1,1,72,72A72.08,72.08,0,0,1,40,112Z"/></svg>',
  'shield-check': '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" fill="currentColor"><path d="M216,56v56c0,96-88,120-88,120S40,208,40,112V56a8,8,0,0,1,8-8H208A8,8,0,0,1,216,56Z" opacity="0.2"/><path d="M208,40H48A16,16,0,0,0,32,56v56c0,52.72,25.52,84.67,46.93,102.19,23.06,18.86,46,26.07,47.06,26.4a8.15,8.15,0,0,0,4,0c1-.33,24-7.54,47.06-26.4C198.48,196.67,224,164.72,224,112V56A16,16,0,0,0,208,40Zm0,72c0,37.07-13.66,65.23-32.58,83.89C159.53,210.61,137.55,220.59,128,224c-9.55-3.41-31.53-13.39-47.42-28.11C61.66,177.23,48,149.07,48,112V56H208Zm-34.34-25.66a8,8,0,0,1,0,11.32l-56,56a8,8,0,0,1-11.32,0l-24-24a8,8,0,0,1,11.32-11.32L112,136.69l50.34-50.35A8,8,0,0,1,173.66,86.34Z"/></svg>',
  'git-branch': '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" fill="currentColor"><path d="M192,160a32,32,0,1,1-32-32A32,32,0,0,1,192,160ZM64,64A32,32,0,1,0,96,96,32,32,0,0,0,64,64Z" opacity="0.2"/><path d="M224,160a40,40,0,1,0-48,39.19V208H128a24,24,0,0,1-24-24V151.47A40,40,0,1,0,72,112.81V143.2A40,40,0,0,0,64,64a40,40,0,0,0-8,79.19v25.62A56.06,56.06,0,0,0,128,224h48v8.81a40,40,0,1,0,16,0V199.19A40,40,0,0,0,224,160ZM64,88a24,24,0,1,1,24,24A24,24,0,0,1,40,88Zm24,96a24,24,0,1,1,24-24A24,24,0,0,1,64,184Zm128,0a24,24,0,1,1,24-24A24,24,0,0,1,192,184Z"/></svg>',
  'notebook': '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" fill="currentColor"><path d="M208,32H72A16,16,0,0,0,56,48V216a16,16,0,0,0,16,16H208a8,8,0,0,0,8-8V40A8,8,0,0,0,208,32Z" opacity="0.2"/><path d="M208,24H72A24,24,0,0,0,48,48V224a8,8,0,0,0,8,8H208a16,16,0,0,0,16-16V40A16,16,0,0,0,208,24ZM72,40H208V216H64V48A8,8,0,0,1,72,40ZM40,48a24,24,0,0,0-.46,4.62L40,56V216a8,8,0,0,1-8-8V48ZM112,88h64a8,8,0,0,1,0,16H112a8,8,0,0,1,0-16Zm-8,40a8,8,0,0,1,8-8h64a8,8,0,0,1,0,16H112A8,8,0,0,1,104,128Z"/></svg>',
  'terminal': '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" fill="currentColor"><path d="M216,40H40A16,16,0,0,0,24,56V200a16,16,0,0,0,16,16H216a16,16,0,0,0,16-16V56A16,16,0,0,0,216,40Z" opacity="0.2"/><path d="M216,32H40A24,24,0,0,0,16,56V200a24,24,0,0,0,24,24H216a24,24,0,0,0,24-24V56A24,24,0,0,0,216,32Zm8,168a8,8,0,0,1-8,8H40a8,8,0,0,1-8-8V56a8,8,0,0,1,8-8H216a8,8,0,0,1,8,8Zm-42.34-93.66a8,8,0,0,1,0,11.32l-40,40a8,8,0,0,1-11.32-11.32L164.69,112,130.34,77.66a8,8,0,0,1,11.32-11.32Zm-48,40a8,8,0,0,1,0,11.32l-40,40a8,8,0,0,1-11.32-11.32L116.69,152,82.34,117.66a8,8,0,0,1,11.32-11.32Z"/></svg>',
  'robot': '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" fill="currentColor"><path d="M200,48H56A24,24,0,0,0,32,72V200a24,24,0,0,0,24,24H200a24,24,0,0,0,24-24V72A24,24,0,0,0,200,48ZM164,168H92a20,20,0,0,1,0-40h72a20,20,0,0,1,0,40Z" opacity="0.2"/><path d="M200,40H136V16a8,8,0,0,0-16,0V40H56A32,32,0,0,0,24,72V200a32,32,0,0,0,32,32H200a32,32,0,0,0,32-32V72A32,32,0,0,0,200,40Zm16,160a16,16,0,0,1-16,16H56a16,16,0,0,1-16-16V72A16,16,0,0,1,56,56H200a16,16,0,0,1,16,16ZM104,120a12,12,0,1,1-12-12A12,12,0,0,1,104,120Zm72,0a12,12,0,1,1-12-12A12,12,0,0,1,176,120Zm-12,28H92a28,28,0,0,0,0,56h72a28,28,0,0,0,0-56Zm-72,16h72a12,12,0,0,1,0,24H92a12,12,0,0,1,0-24Z"/></svg>',
  'lightning': '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" fill="currentColor"><path d="M96,240,112,160H48L160,16,144,96h64Z" opacity="0.2"/><path d="M215.79,118.17a8,8,0,0,0-5-5.66L153.18,90.9l14.66-73.33a8,8,0,0,0-13.69-7l-112,120a8,8,0,0,0,3,12.9l57.63,21.61L88.16,238.43a8,8,0,0,0,13.69,7l112-120A8,8,0,0,0,215.79,118.17ZM109.37,214l10.47-52.38a8,8,0,0,0-5-9L60.08,132.46l86.54-92.81L136.15,92a8,8,0,0,0,5,9l54.73,20.54Z"/></svg>',
  'brain': '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" fill="currentColor"><path d="M128,40V216A88,88,0,0,1,128,40Z" opacity="0.2"/><path d="M248,132a56.06,56.06,0,0,0-32-50.61,60,60,0,0,0-88-50.11,60,60,0,0,0-88,50.11A56,56,0,0,0,8,132a56.53,56.53,0,0,0,24,46.22A52,52,0,0,0,128,211.42a52,52,0,0,0,96-32.64A56.53,56.53,0,0,0,248,132ZM136,197.39V120a8,8,0,0,0-16,0v77.39a36,36,0,0,1-64-22.45,55.87,55.87,0,0,0,24-4.35,8,8,0,0,0-6.55-14.6A40.07,40.07,0,0,1,24,132a40.36,40.36,0,0,1,17.47-33.27,8,8,0,0,0,3.34-8.06,43.22,43.22,0,0,1-.81-8.17,44.05,44.05,0,0,1,44-44,43.37,43.37,0,0,1,20.51,5.12,8,8,0,0,0,10.18-2.44A44,44,0,0,1,182,60.32a8,8,0,0,0,3.34,8.06A40,40,0,0,1,180.59,160a8,8,0,1,0-6.55,14.6,55.87,55.87,0,0,0,24,4.35A36,36,0,0,1,136,197.39Z"/></svg>',
  'bug': '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" fill="currentColor"><path d="M200,128a72,72,0,0,1-144,0V104H200Z" opacity="0.2"/><path d="M168,92a12,12,0,1,1-12-12A12,12,0,0,1,168,92Zm-68-12a12,12,0,1,0,12,12A12,12,0,0,0,100,80Zm128,56a8,8,0,0,1-8,8H196.26a79.67,79.67,0,0,1-10.09,34.93l26.49,26.49a8,8,0,0,1-11.32,11.32l-27.85-27.86a79.72,79.72,0,0,1-91,0L54.66,216.74a8,8,0,0,1-11.32-11.32l26.49-26.49A79.67,79.67,0,0,1,59.74,144H36a8,8,0,0,1,0-16H59.74a79.67,79.67,0,0,1,10.09-34.93L43.34,66.58a8,8,0,0,1,11.32-11.32l27.85,27.86a79.72,79.72,0,0,1,91,0l27.85-27.86a8,8,0,0,1,11.32,11.32L186.17,93.07A79.67,79.67,0,0,1,196.26,128H220A8,8,0,0,1,228,136ZM180,128a52,52,0,0,0-104,0v0h0a52,52,0,0,0,104,0Z"/></svg>',
  'rocket': '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" fill="currentColor"><path d="M94.81,196.72,76.25,215.28A16,16,0,0,1,48,204V152l34.81-11.27A195,195,0,0,0,94.81,196.72Zm66.38-55.99A195,195,0,0,0,217.18,128.72L240,104V52a16,16,0,0,0-11.28-15.28Z" opacity="0.2"/><path d="M152,224a8,8,0,0,1-8,8H112a8,8,0,0,1,0-16h32A8,8,0,0,1,152,224Zm73.69-183.36A16,16,0,0,0,214,32.42C167.21,35.94,122.47,57.18,92.68,90.61L40,107.21a16,16,0,0,0-10.53,10l-15.06,41.7a16,16,0,0,0,3.79,17L40,197.66V232a8,8,0,0,0,13.66,5.66L77,214.34a16,16,0,0,0,17,3.79l41.7-15.06a16,16,0,0,0,10-10.53L162.39,140c33.43-29.79,54.67-74.53,58.19-121.32A16,16,0,0,0,225.69,40.64ZM56,189.66,45.66,179.32l11.3-31.3L83.8,174.87ZM133.84,173l-43.16,15.59L62.48,160.41,78.07,117.24a157.28,157.28,0,0,1,84.89-63.17l39,39A157.28,157.28,0,0,1,133.84,173ZM152,108a20,20,0,1,0-20-20A20,20,0,0,0,152,108Z"/></svg>',
  'lock': '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" fill="currentColor"><path d="M208,88H48a8,8,0,0,0-8,8V208a8,8,0,0,0,8,8H208a8,8,0,0,0,8-8V96A8,8,0,0,0,208,88Zm-80,72a12,12,0,1,1,12-12A12,12,0,0,1,128,160Z" opacity="0.2"/><path d="M208,80H176V56a48,48,0,0,0-96,0V80H48A16,16,0,0,0,32,96V208a16,16,0,0,0,16,16H208a16,16,0,0,0,16-16V96A16,16,0,0,0,208,80ZM96,56a32,32,0,0,1,64,0V80H96ZM208,208H48V96H208Zm-80-36a20,20,0,1,0-20-20A20,20,0,0,0,128,172Z"/></svg>',
  'database': '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" fill="currentColor"><path d="M208,80c0,17.67-35.82,32-80,32S48,97.67,48,80s35.82-32,80-32S208,62.33,208,80Z" opacity="0.2"/><path d="M128,40C77.31,40,40,58.17,40,80v96c0,21.83,37.31,40,88,40s88-18.17,88-40V80C216,58.17,178.69,40,128,40Zm0,16c45,0,72,16.3,72,24s-27,24-72,24S56,88.3,56,80,83,56,128,56Zm0,144c-45,0-72-16.3-72-24V138.58C75.32,148.86,99.93,156,128,156s52.68-7.14,72-17.42V176C200,183.7,173,200,128,200Zm72-88c0,7.7-27,24-72,24s-72-16.3-72-24V106.58C75.32,116.86,99.93,124,128,124s52.68-7.14,72-17.42Z"/></svg>',
  'globe': '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" fill="currentColor"><circle cx="128" cy="128" r="88" opacity="0.2"/><path d="M128,24A104,104,0,1,0,232,128,104.11,104.11,0,0,0,128,24Zm87.63,96H175.8c-1.41-28.46-10.27-55.45-25.12-77A88.2,88.2,0,0,1,215.63,120ZM128,215.14C108.49,198.12,94,166.33,92.22,136h71.56C162,166.33,147.51,198.12,128,215.14ZM92.22,120C94,89.67,108.49,57.88,128,40.86,147.51,57.88,162,89.67,163.78,120Zm13.1-77C90.47,64.55,81.61,91.54,80.2,120H40.37A88.2,88.2,0,0,1,105.32,43ZM40.37,136H80.2c1.41,28.46,10.27,55.45,25.12,77A88.2,88.2,0,0,1,40.37,136Zm110.31,77c14.85-21.56,23.71-48.55,25.12-77h39.83A88.2,88.2,0,0,1,150.68,213Z"/></svg>',
  'megaphone': '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" fill="currentColor"><path d="M200,80v96L40,224V32Z" opacity="0.2"/><path d="M228.54,86.66l-176.06-54A16,16,0,0,0,32,48V208a16.05,16.05,0,0,0,16,16,16.58,16.58,0,0,0,4.49-.63L128,201.27V232a8,8,0,0,0,8,8h32a8,8,0,0,0,8-8V194.65l52.54-16.13A16.07,16.07,0,0,0,240,163V93A16.07,16.07,0,0,0,228.54,86.66ZM160,224H144V204.33l16-4.92ZM48,208V48l152,46.67V161.33Z"/></svg>',
  'eye': '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" fill="currentColor"><path d="M128,56C48,56,16,128,16,128s32,72,112,72,112-72,112-72S208,56,128,56Zm0,112a40,40,0,1,1,40-40A40,40,0,0,1,128,168Z" opacity="0.2"/><path d="M247.31,124.76c-.35-.79-8.82-19.58-27.65-38.41C194.57,61.26,162.88,48,128,48S61.43,61.26,36.34,86.35C17.51,105.18,9,124,8.69,124.76a8,8,0,0,0,0,6.5c.35.79,8.82,19.57,27.65,38.4C61.43,194.74,93.12,208,128,208s66.57-13.26,91.66-38.34c18.83-18.83,27.3-37.61,27.65-38.4A8,8,0,0,0,247.31,124.76ZM128,192c-30.78,0-57.67-11.19-79.93-33.26A130.33,130.33,0,0,1,25.7,128,130.33,130.33,0,0,1,48.07,97.26C70.33,75.19,97.22,64,128,64s57.67,11.19,79.93,33.26A130.33,130.33,0,0,1,230.3,128C223.94,139.42,192.33,192,128,192Zm0-112a48,48,0,1,0,48,48A48.05,48.05,0,0,0,128,80Zm0,80a32,32,0,1,1,32-32A32,32,0,0,1,128,160Z"/></svg>',
  'palette': '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" fill="currentColor"><path d="M224,128c0,52.93-43.07,96-96,96a96,96,0,0,1,0-192C181.07,32,224,67,224,98.67,224,124.8,204.8,144,180,144H156a20,20,0,0,0-12,36C152,186.67,183.39,202.67,224,128Z" opacity="0.2"/><path d="M200.77,53.89A103.27,103.27,0,0,0,128,24h-1.07A104,104,0,0,0,24,128c0,43,26.58,79.07,69.36,94.17A24,24,0,0,0,124,200a24,24,0,0,0,24-24,24,24,0,0,1,24-24h28a56.06,56.06,0,0,0,56-56C256,69.84,239.66,53.89,200.77,53.89ZM200,136H172a40,40,0,0,0-40,40,8,8,0,0,1-8,8,8,8,0,0,1-3-.57C84.56,170.21,40,143.52,40,128A88,88,0,0,1,128.77,40C201.09,40.36,240,75.43,240,96A40,40,0,0,1,200,136ZM136,72a12,12,0,1,1-12-12A12,12,0,0,1,136,72Zm-44,24a12,12,0,1,1-12-12A12,12,0,0,1,92,96Zm0,48a12,12,0,1,1-12-12A12,12,0,0,1,92,144Zm88-48a12,12,0,1,1-12-12A12,12,0,0,1,180,96Z"/></svg>',
  'book': '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" fill="currentColor"><path d="M208,24H72A32,32,0,0,0,40,56V224a8,8,0,0,0,8,8H192a8,8,0,0,0,0-16H56a16,16,0,0,1,16-16H208a8,8,0,0,0,8-8V32A8,8,0,0,0,208,24Z" opacity="0.2"/><path d="M208,16H72A40,40,0,0,0,32,56V224a8,8,0,0,0,8,8H192a8,8,0,0,0,0-16H48a24,24,0,0,1,24-24H208a8,8,0,0,0,8-8V24A8,8,0,0,0,208,16Zm-8,160H72a39.81,39.81,0,0,0-24,8.11V56A24,24,0,0,1,72,32H200Z"/></svg>',
  'users': '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" fill="currentColor"><path d="M136,108a52,52,0,1,1-52-52A52,52,0,0,1,136,108Z" opacity="0.2"/><path d="M117.25,157.92a60,60,0,1,0-66.5,0A95.83,95.83,0,0,0,3.53,195.63a8,8,0,1,0,13.4,8.74A80,80,0,0,1,84,168a80,80,0,0,1,67.07,36.37,8,8,0,0,0,13.4-8.74A95.83,95.83,0,0,0,117.25,157.92ZM40,108a44,44,0,1,1,44,44A44.05,44.05,0,0,1,40,108Zm210.14,98.7a8,8,0,0,1-11.07-2.33A79.83,79.83,0,0,0,172,168a8,8,0,0,1,0-16,44,44,0,1,0-16.81-84.87,8,8,0,1,1-6.11-14.79,60,60,0,0,1,45.67,103.58,95.83,95.83,0,0,1,47.72,37.71A8,8,0,0,1,250.14,206.7Z"/></svg>',
  'heartbeat': '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" fill="currentColor"><path d="M232,108a52,52,0,0,1-15.23,36.77L128,236,39.23,144.77A52,52,0,0,1,112,68.18L128,84l16-15.82A52,52,0,0,1,232,108Z" opacity="0.2"/><path d="M128,224a8,8,0,0,1-5.66-2.34l-88.76-88.77a60,60,0,0,1,84.88-84.88L128,57.55,137.54,48A60,60,0,1,1,222.42,133L133.66,221.66A8,8,0,0,1,128,224ZM92,56A44,44,0,0,0,60.9,131.12L128,198.23l67.12-67.11A44,44,0,0,0,132.88,68.88l-4.88,4.88L123.32,79A8,8,0,0,1,112,79L98.34,65.32A43.7,43.7,0,0,0,92,56Z"/></svg>',
  'gauge': '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" fill="currentColor"><path d="M224,128a96,96,0,1,1-96-96A96,96,0,0,1,224,128Z" opacity="0.2"/><path d="M207.06,80.67A104,104,0,1,0,232,128,103.34,103.34,0,0,0,207.06,80.67ZM128,216A88,88,0,1,1,216,128,87.55,87.55,0,0,1,128,216Zm45.66-93.66a8,8,0,0,1,0,11.32l-40,40a8,8,0,0,1-11.32-11.32l40-40A8,8,0,0,1,173.66,122.34ZM92,100a12,12,0,1,1,12,12A12,12,0,0,1,92,100Zm72,0a12,12,0,1,1,12,12A12,12,0,0,1,164,100ZM80,148a12,12,0,1,1,12,12A12,12,0,0,1,80,148Z"/></svg>',
  'code': '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" fill="currentColor"><path d="M216,40H40A16,16,0,0,0,24,56V200a16,16,0,0,0,16,16H216a16,16,0,0,0,16-16V56A16,16,0,0,0,216,40Z" opacity="0.2"/><path d="M216,32H40A24,24,0,0,0,16,56V200a24,24,0,0,0,24,24H216a24,24,0,0,0,24-24V56A24,24,0,0,0,216,32Zm8,168a8,8,0,0,1-8,8H40a8,8,0,0,1-8-8V56a8,8,0,0,1,8-8H216a8,8,0,0,1,8,8Zm-50.34-77.66a8,8,0,0,1,0,11.32l-24,24a8,8,0,0,1-11.32-11.32L156.69,128,138.34,109.66a8,8,0,0,1,11.32-11.32Zm-80,0,24-24a8,8,0,0,1,11.32,11.32L110.63,128l18.35,18.34a8,8,0,0,1-11.32,11.32l-24-24A8,8,0,0,1,93.66,122.34Z"/></svg>',
  'clipboard': '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" fill="currentColor"><path d="M200,40H176a8,8,0,0,0-8-8H88a8,8,0,0,0-8,8H56A16,16,0,0,0,40,56V216a16,16,0,0,0,16,16H200a16,16,0,0,0,16-16V56A16,16,0,0,0,200,40Z" opacity="0.2"/><path d="M200,32H163.74a47.92,47.92,0,0,0-71.48,0H56A16,16,0,0,0,40,48V216a16,16,0,0,0,16,16H200a16,16,0,0,0,16-16V48A16,16,0,0,0,200,32Zm-72,0a32,32,0,0,1,32,32H96A32,32,0,0,1,128,32Zm72,184H56V48H82.75A47.93,47.93,0,0,0,80,64v8a8,8,0,0,0,8,8h80a8,8,0,0,0,8-8V64a47.93,47.93,0,0,0-2.75-16H200Z"/></svg>',
  'gear': '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" fill="currentColor"><circle cx="128" cy="128" r="40" opacity="0.2"/><path d="M128,80a48,48,0,1,0,48,48A48.05,48.05,0,0,0,128,80Zm0,80a32,32,0,1,1,32-32A32,32,0,0,1,128,160Zm88-29.84q.06-2.16,0-4.32l14.92-18.64a8,8,0,0,0,1.48-7.06,107.21,107.21,0,0,0-10.88-26.16,8,8,0,0,0-6-3.93l-23.72-2.64q-1.48-1.56-3-3L186,40.54a8,8,0,0,0-3.94-6,107.71,107.71,0,0,0-26.16-10.87,8,8,0,0,0-7.06,1.49L130.16,40Q128,40,125.84,40L107.2,25.11a8,8,0,0,0-7.06-1.48A107.6,107.6,0,0,0,73.98,34.51a8,8,0,0,0-3.93,6l-2.64,23.72q-1.56,1.49-3,3L40.54,70a8,8,0,0,0-6,3.94,107.71,107.71,0,0,0-10.87,26.16,8,8,0,0,0,1.49,7.06L40,125.84q-.06,2.16,0,4.32L25.11,148.8a8,8,0,0,0-1.48,7.06,107.21,107.21,0,0,0,10.88,26.16,8,8,0,0,0,6,3.93l23.72,2.64q1.49,1.56,3,3L70,215.46a8,8,0,0,0,3.94,6,107.71,107.71,0,0,0,26.16,10.87,8,8,0,0,0,7.06-1.49L125.84,216q2.16.06,4.32,0l18.64,14.92a8,8,0,0,0,7.06,1.48,107.21,107.21,0,0,0,26.16-10.88,8,8,0,0,0,3.93-6l2.64-23.72q1.56-1.48,3-3L215.46,186a8,8,0,0,0,6-3.94,107.71,107.71,0,0,0,10.87-26.16,8,8,0,0,0-1.49-7.06Zm-16.1-6.5a73.93,73.93,0,0,1,0,8.68,8,8,0,0,0,1.74,5.68l14.19,17.73a91.57,91.57,0,0,1-6.23,15L187.11,168a8,8,0,0,0-5.1,2.64,74.11,74.11,0,0,1-6.14,6.14A8,8,0,0,0,173.22,182l-2.51,22.58a91.32,91.32,0,0,1-15,6.23l-17.74-14.19a8,8,0,0,0-5-1.75h-.67a73.68,73.68,0,0,1-8.67,0,8,8,0,0,0-5.69,1.74L100.17,210.8a91.57,91.57,0,0,1-15-6.23L82.66,182.05A8,8,0,0,0,80,176.9a74.11,74.11,0,0,1-6.14-6.14,8,8,0,0,0-5.1-2.64l-22.58-2.51a91.32,91.32,0,0,1-6.23-15l14.19-17.74a8,8,0,0,0,1.74-5.67,73.93,73.93,0,0,1,0-8.68A8,8,0,0,0,54.14,113.5L40,95.77a91.57,91.57,0,0,1,6.23-15L68.66,83.3A8,8,0,0,0,73.76,80.66a74.11,74.11,0,0,1,6.14-6.14A8,8,0,0,0,82.55,69.42L85.06,46.84a91.32,91.32,0,0,1,15-6.23l17.74,14.19a8,8,0,0,0,5.68,1.74,73.93,73.93,0,0,1,8.68,0,8,8,0,0,0,5.68-1.74l17.73-14.19a91.57,91.57,0,0,1,15,6.23l2.51,22.58a8,8,0,0,0,2.64,5.1,74.11,74.11,0,0,1,6.14,6.14,8,8,0,0,0,5.1,2.64l22.58,2.51a91.32,91.32,0,0,1,6.23,15l-14.19,17.74A8,8,0,0,0,199.9,123.66Z"/></svg>',
};

// Role → icon mapping
const ROLE_ICON_MAP = {
  'supervisor': 'crown', 'lead': 'crown', 'director': 'crown',
  'engineer': 'wrench', 'builder': 'wrench', 'developer': 'wrench', 'coder': 'code', 'dev': 'code',
  'scout': 'magnifying-glass', 'researcher': 'magnifying-glass', 'investigator': 'magnifying-glass',
  'qa': 'shield-check', 'q-a': 'shield-check', 'quality': 'shield-check', 'tester': 'shield-check', 'validator': 'shield-check',
  'git': 'git-branch', 'git-agent': 'git-branch', 'vcs': 'git-branch',
  'chronicler': 'notebook', 'observer': 'notebook', 'logger': 'notebook',
  'gurvinder': 'terminal', 'operator': 'terminal', 'admin': 'terminal', 'root': 'terminal',
};

// Role → color mapping
const ROLE_COLOR_MAP = {
  'supervisor': '#b388ff', 'lead': '#b388ff', 'director': '#b388ff',
  'engineer': '#448aff', 'builder': '#448aff', 'developer': '#448aff', 'coder': '#448aff', 'dev': '#448aff',
  'scout': '#18ffff', 'researcher': '#18ffff', 'investigator': '#18ffff',
  'qa': '#ff5252', 'q-a': '#ff5252', 'quality': '#ff5252', 'tester': '#ff5252', 'validator': '#ff5252',
  'git': '#ffd740', 'git-agent': '#ffd740', 'vcs': '#ffd740',
  'chronicler': '#ff80ab', 'observer': '#ff80ab', 'logger': '#ff80ab',
  'gurvinder': '#ff9100', 'operator': '#ff9100',
};

const EXTRA_COLOR_SWATCHES = ['#64ffda', '#b9f6ca', '#ff6e40', '#8c9eff', '#ffcc80', '#84ffff', '#f48fb1', '#ce93d8'];

function resolveAgentIcon(agent) {
  // 1. Stored icon
  if (agent.icon && AVATAR_ICONS[agent.icon]) return agent.icon;
  // 2. Role keyword match
  const name = (agent.name || '').toLowerCase();
  for (const [kw, icon] of Object.entries(ROLE_ICON_MAP)) {
    if (name.includes(kw)) return icon;
  }
  // 3. Fallback
  return 'robot';
}

function resolveAgentColor(agent) {
  // 1. Stored color
  if (agent.color) return agent.color;
  // 2. Role keyword match
  const name = (agent.name || '').toLowerCase();
  for (const [kw, c] of Object.entries(ROLE_COLOR_MAP)) {
    if (name.includes(kw)) return c;
  }
  // 3. Hash-based fallback
  let hash = 0;
  for (let i = 0; i < name.length; i++) hash = ((hash << 5) - hash + name.charCodeAt(i)) | 0;
  return EXTRA_COLOR_SWATCHES[Math.abs(hash) % EXTRA_COLOR_SWATCHES.length];
}

function renderAvatarCircle(agent, size) {
  size = size || 40;
  const iconSize = Math.round(size * 0.55);
  const iconKey = resolveAgentIcon(agent);
  const agentColor = resolveAgentColor(agent);
  const svgHtml = AVATAR_ICONS[iconKey] || AVATAR_ICONS['robot'];
  return `<div class="agent-avatar" style="width:${size}px;height:${size}px;min-width:${size}px;background:${agentColor}"><div class="agent-avatar-icon" style="width:${iconSize}px;height:${iconSize}px">${svgHtml}</div></div>`;
}
```

NOTE: The SVG paths above are actual Phosphor duotone icons. The implementer MUST fetch the real SVG content from https://phosphoricons.com for each icon. The paths shown are the real paths — use them as-is. Each SVG has both an `opacity="0.2"` fill path (the duotone background) and a full-opacity outline path.

- [ ] **Step 2: Add CSS for avatar circles**

Add in the global CSS section (NOT inside the mobile media query), after the existing `.dot` styles (around line 180):

```css
  .agent-avatar {
    border-radius: 50%;
    display: flex;
    align-items: center;
    justify-content: center;
    flex-shrink: 0;
  }

  .agent-avatar-icon {
    display: flex;
    align-items: center;
    justify-content: center;
  }

  .agent-avatar-icon svg {
    width: 100%;
    height: 100%;
    fill: white;
  }
```

- [ ] **Step 3: Commit**

```bash
git add static/index.html
git commit -m "feat(m2): step 2 — Phosphor duotone icon library + color/icon resolution"
```

---

### Task 3: Desktop Agent Cards — Add Avatar Circles

**Files:**
- Modify: `static/index.html` — `renderAgents()` function

This task adds avatar circles to the existing desktop agent cards. Additive change only — the card structure stays the same, we prepend an avatar.

- [ ] **Step 1: Update the Gurvinder operator card**

In `renderAgents()`, find the gurvinder card HTML:
```javascript
  gCard.innerHTML = `
    <div class="ac-row1">
      <span class="dot active"></span>
      <span class="ac-name" style="color:${color('gurvinder')}">gurvinder</span>
    </div>
    <div class="ac-row2">
      <span class="ac-role">Operator</span>
    </div>
  `;
```

Replace with:
```javascript
  const gColor = resolveAgentColor({name: 'gurvinder', color: null});
  gCard.innerHTML = `
    <div class="ac-row1">
      ${renderAvatarCircle({name: 'gurvinder'}, 28)}
      <span class="dot active"></span>
      <span class="ac-name" style="color:${gColor}">gurvinder</span>
    </div>
    <div class="ac-row2">
      <span class="ac-role">Operator</span>
    </div>
  `;
```

- [ ] **Step 2: Update the active agent card**

In the active agents loop, find where the card HTML is built. Replace the `color(a.name)` call with `resolveAgentColor(a)` for the name color, and add the avatar circle.

Find:
```javascript
    card.innerHTML = `
      <div class="ac-row1">
        <span class="ac-drag-handle" title="Drag to reorder">⠿</span>
        <span class="dot ${dotClass}"></span>
        <span class="ac-name" style="color:${color(a.name)}">${a.name}${dynBadge}</span>
        <div class="ac-actions">${btns}</div>
      </div>
```

Replace with:
```javascript
    const agentColor = resolveAgentColor(a);
    card.innerHTML = `
      <div class="ac-row1">
        <span class="ac-drag-handle" title="Drag to reorder">⠿</span>
        ${renderAvatarCircle(a, 28)}
        <span class="dot ${dotClass}"></span>
        <span class="ac-name" style="color:${agentColor}">${a.name}${dynBadge}</span>
        <div class="ac-actions">${btns}</div>
      </div>
```

- [ ] **Step 3: Update the `color()` function references in chat**

The existing `color(name)` function in the JS (line ~1759) uses the old COLORS dict. Update it to use `resolveAgentColor` when an agent roster entry exists:

Find the `color` function:
```javascript
const color = n => COLORS[n] || '#7a8a9e';
```

Replace with:
```javascript
const color = n => {
  // Check if this is a known agent with a stored color
  const agent = agentRoster.find(a => a.name === n);
  if (agent) return resolveAgentColor(agent);
  return COLORS[n] || '#7a8a9e';
};
```

- [ ] **Step 4: Commit**

```bash
git add static/index.html
git commit -m "feat(m2): step 3 — desktop avatar circles + unified color resolution"
```

---

### Task 4: Desktop Creation Form — Color + Icon Pickers

**Files:**
- Modify: `static/index.html` — drawer HTML and JS

This task adds color swatch picker and icon grid picker to the "+ new" agent creation form.

- [ ] **Step 1: Add picker HTML to the drawer**

Find the `<!-- Model -->` comment in the drawer HTML (line ~1727). Insert BEFORE it:

```html
    <!-- Color -->
    <div class="drawer-field">
      <label class="drawer-label">Color</label>
      <div id="dColorPicker" class="color-picker">
        <div class="color-swatch selected" data-color="#b388ff" style="background:#b388ff" title="Purple"></div>
        <div class="color-swatch" data-color="#448aff" style="background:#448aff" title="Blue"></div>
        <div class="color-swatch" data-color="#18ffff" style="background:#18ffff" title="Cyan"></div>
        <div class="color-swatch" data-color="#ff5252" style="background:#ff5252" title="Red"></div>
        <div class="color-swatch" data-color="#ffd740" style="background:#ffd740" title="Gold"></div>
        <div class="color-swatch" data-color="#ff80ab" style="background:#ff80ab" title="Pink"></div>
        <div class="color-swatch" data-color="#ff9100" style="background:#ff9100" title="Orange"></div>
        <div class="color-swatch" data-color="#7a8a9e" style="background:#7a8a9e" title="Grey"></div>
        <div class="color-swatch" data-color="#64ffda" style="background:#64ffda" title="Teal"></div>
        <div class="color-swatch" data-color="#b9f6ca" style="background:#b9f6ca" title="Lime"></div>
        <div class="color-swatch" data-color="#ff6e40" style="background:#ff6e40" title="Coral"></div>
        <div class="color-swatch" data-color="#8c9eff" style="background:#8c9eff" title="Indigo"></div>
        <div class="color-swatch" data-color="#ffcc80" style="background:#ffcc80" title="Amber"></div>
        <div class="color-swatch" data-color="#84ffff" style="background:#84ffff" title="Mint"></div>
        <div class="color-swatch" data-color="#f48fb1" style="background:#f48fb1" title="Salmon"></div>
        <div class="color-swatch" data-color="#ce93d8" style="background:#ce93d8" title="Lavender"></div>
      </div>
    </div>

    <!-- Icon -->
    <div class="drawer-field">
      <label class="drawer-label">Icon</label>
      <div id="dIconPicker" class="icon-picker"></div>
    </div>
```

- [ ] **Step 2: Add CSS for pickers**

Add in the global CSS section (after the `.drawer-textarea` styles):

```css
  .color-picker {
    display: flex;
    flex-wrap: wrap;
    gap: 6px;
    padding: 4px 0;
  }

  .color-swatch {
    width: 28px;
    height: 28px;
    border-radius: 50%;
    cursor: pointer;
    border: 2px solid transparent;
    transition: border-color 0.15s, transform 0.1s;
  }

  .color-swatch:hover { transform: scale(1.15); }
  .color-swatch.selected { border-color: white; }

  .icon-picker {
    display: grid;
    grid-template-columns: repeat(5, 1fr);
    gap: 4px;
    padding: 4px 0;
  }

  .icon-cell {
    width: 40px;
    height: 40px;
    display: flex;
    align-items: center;
    justify-content: center;
    border-radius: 8px;
    cursor: pointer;
    border: 2px solid transparent;
    background: var(--bg-deep);
    transition: border-color 0.15s;
  }

  .icon-cell:hover { background: var(--bg-card-hover); }
  .icon-cell.selected { border-color: var(--green); }

  .icon-cell svg { width: 22px; height: 22px; fill: var(--text-secondary); }
```

- [ ] **Step 3: Add picker JavaScript**

In the script section, find where the drawer launch button handler is set up. Add after it:

```javascript
// ═══════════ Color + Icon Pickers ═══════════
const $colorPicker = $('dColorPicker');
const $iconPicker = $('dIconPicker');
let selectedColor = '#b388ff';
let selectedIcon = 'crown';

// Populate icon picker grid
if ($iconPicker) {
  Object.entries(AVATAR_ICONS).forEach(([key, svg]) => {
    const cell = document.createElement('div');
    cell.className = 'icon-cell' + (key === selectedIcon ? ' selected' : '');
    cell.dataset.icon = key;
    cell.innerHTML = svg;
    cell.onclick = () => {
      $iconPicker.querySelectorAll('.icon-cell').forEach(c => c.classList.remove('selected'));
      cell.classList.add('selected');
      selectedIcon = key;
    };
    $iconPicker.appendChild(cell);
  });
}

// Color picker click handler
if ($colorPicker) {
  $colorPicker.querySelectorAll('.color-swatch').forEach(swatch => {
    swatch.onclick = () => {
      $colorPicker.querySelectorAll('.color-swatch').forEach(s => s.classList.remove('selected'));
      swatch.classList.add('selected');
      selectedColor = swatch.dataset.color;
    };
  });
}

// Auto-select color and icon when role type changes
const $roleType = $('dRoleType');
if ($roleType) {
  $roleType.addEventListener('change', () => {
    const rt = $roleType.value;
    if (rt && ROLE_COLOR_MAP[rt]) {
      selectedColor = ROLE_COLOR_MAP[rt];
      if ($colorPicker) {
        $colorPicker.querySelectorAll('.color-swatch').forEach(s => {
          s.classList.toggle('selected', s.dataset.color === selectedColor);
        });
      }
    }
    if (rt && ROLE_ICON_MAP[rt]) {
      selectedIcon = ROLE_ICON_MAP[rt];
      if ($iconPicker) {
        $iconPicker.querySelectorAll('.icon-cell').forEach(c => {
          c.classList.toggle('selected', c.dataset.icon === selectedIcon);
        });
      }
    }
  });
}
```

- [ ] **Step 4: Update the launch handler to send color and icon**

Find where the agent creation `fetch('/api/agents/create', ...)` call builds the request body. Add `color` and `icon` to the body.

Find the body object (it will have `name`, `directory`, `role`, etc.). Add:
```javascript
        color: selectedColor,
        icon: selectedIcon,
```

- [ ] **Step 5: Commit**

```bash
git add static/index.html
git commit -m "feat(m2): step 4 — color and icon pickers in desktop creation form"
```

---

### Task 5: Mobile Agent Cards Redesign

**Files:**
- Modify: `static/index.html` — mobile CSS + renderAgents() function

This is the core mobile task — redesigning the agent cards for iPhone.

- [ ] **Step 1: Add mobile agent card CSS**

Inside the `@media (max-width: 767px)` block, find the existing agent card overrides:
```css
    /* ═══ Agent cards ═══ */
    .ac { padding: 12px 14px; }
    .abtn { padding: 6px 12px; font-size: 10px; min-height: 34px; }
```

Replace with:

```css
    /* ═══ Agent cards — mobile redesign ═══ */
    .ac {
      display: flex;
      align-items: center;
      gap: 12px;
      padding: 12px 14px;
      border-radius: 14px;
      background: var(--bg-card);
      margin-bottom: 8px;
      border-left: none;
      cursor: pointer;
      -webkit-tap-highlight-color: transparent;
    }

    .ac.off { opacity: 0.6; }

    .ac-operator {
      background: var(--bg-elevated);
    }

    .ac-row1 {
      display: flex;
      align-items: center;
      gap: 0;
      flex: 1;
      min-width: 0;
    }

    .ac-drag-handle { display: none; }
    .ac-actions { display: none; }
    .ac-row2 { display: none; }
    .ac-activity { display: none; }
    .ac-progress { display: none; }
    .ac-blocker { display: none; }
    .ac-stalled-text { display: none; }
    .ac-dead-warning { display: none; }
    .ac-commit { display: none; }
    .ac-sep { display: none; }
    .ac-dynamic { display: none; }

    .ac .mobile-card-body {
      display: flex;
      flex: 1;
      min-width: 0;
    }

    .ac .mobile-card-info {
      flex: 1;
      min-width: 0;
    }

    .ac .mobile-card-name {
      font-family: 'Source Sans 3', -apple-system, sans-serif;
      font-size: 15px;
      font-weight: 600;
      white-space: nowrap;
      overflow: hidden;
      text-overflow: ellipsis;
    }

    .ac .mobile-card-role {
      font-family: 'Source Sans 3', -apple-system, sans-serif;
      font-size: 13px;
      color: var(--text-dim);
      white-space: nowrap;
      overflow: hidden;
      text-overflow: ellipsis;
      margin-top: 2px;
    }

    .ac .mobile-card-status {
      display: flex;
      flex-direction: column;
      align-items: flex-end;
      gap: 2px;
      flex-shrink: 0;
      margin-left: 8px;
    }

    .ac .mobile-status-row {
      display: flex;
      align-items: center;
      gap: 4px;
    }

    .ac .mobile-status-dot {
      width: 8px;
      height: 8px;
      border-radius: 50%;
      flex-shrink: 0;
    }

    .ac .mobile-status-word {
      font-family: 'JetBrains Mono', monospace;
      font-size: 11px;
    }

    .ac .mobile-status-time {
      font-family: 'JetBrains Mono', monospace;
      font-size: 11px;
      color: var(--text-dim);
    }

    .abtn { display: none; }

    /* Presence colors */
    .mobile-status-dot.active { background: var(--green); }
    .mobile-status-dot.busy { background: var(--yellow); }
    .mobile-status-dot.typing { background: var(--cyan); }
    .mobile-status-dot.session { background: var(--text-dim); }
    .mobile-status-dot.offline { background: #555; }

    .mobile-status-word.active { color: var(--green); }
    .mobile-status-word.busy { color: var(--yellow); }
    .mobile-status-word.typing { color: var(--cyan); }
    .mobile-status-word.session { color: var(--text-dim); }
    .mobile-status-word.offline { color: #555; }
```

- [ ] **Step 2: Update renderAgents() to inject mobile card HTML**

The key insight: on mobile, the desktop card HTML is hidden via CSS (`ac-row1` displays none for most children, `ac-row2` hidden, etc.). But we need to inject ADDITIONAL mobile-specific elements into each card. The cleanest approach: after building the desktop card HTML, append mobile-specific HTML that's only visible on mobile.

At the end of the active agent card building (just BEFORE `$agents.appendChild(card);`), add:

```javascript
    // Mobile card overlay — hidden on desktop, visible on mobile
    const isMobile = window.innerWidth < 768;
    const PRESENCE_LABELS = { active: 'active', busy: 'working', typing: 'thinking', session: 'no claude', offline: 'offline' };
    const presenceLabel = blockedBy ? 'blocked' : (stalled ? `stalled ${stalledMin}m` : (PRESENCE_LABELS[presence] || presence));
    const presenceClass = blockedBy ? 'offline' : (stalled ? 'busy' : presence);

    const mobileHtml = `
      <div class="mobile-card-body">
        <div class="mobile-card-info">
          <div class="mobile-card-name" style="color:${agentColor}">${a.name}</div>
          <div class="mobile-card-role">${role || ''}</div>
        </div>
        <div class="mobile-card-status">
          <div class="mobile-status-row">
            <span class="mobile-status-dot ${presenceClass}"></span>
            <span class="mobile-status-word ${presenceClass}">${presenceLabel}</span>
          </div>
        </div>
      </div>
    `;
    card.insertAdjacentHTML('beforeend', mobileHtml);

    // Mobile tap handler — open bottom sheet
    if (isMobile) {
      card.onclick = (e) => {
        if (e.target.closest('.abtn')) return; // Don't interfere with button clicks
        showBottomSheet(a.name.toUpperCase(), [
          { icon: SVG_ICONS.chat, label: 'Message', action: 'msg' },
          { icon: SVG_ICONS.eye, label: 'View Activity', action: 'activity' },
          { icon: '<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><line x1="12" y1="16" x2="12" y2="12"/><line x1="12" y1="8" x2="12.01" y2="8"/></svg>', label: 'Details', action: 'details' },
        ], (item) => {
          if (item.action === 'msg') {
            $target.value = a.name;
            if ($inputTarget) $inputTarget.textContent = `@${a.name} ▼`;
            switchTab('chat');
            $input.focus();
          } else if (item.action === 'activity') {
            const items = [];
            items.push({ label: `Presence: ${presenceLabel}` });
            if (activity) items.push({ label: `Activity: ${activity}` });
            if (task) items.push({ label: `Task: ${task}` });
            if (lastCommit) items.push({ label: `Last commit: ${lastCommit.hash} ${lastCommit.message}` });
            showBottomSheet('Activity — ' + a.name, items, () => {});
          } else if (item.action === 'details') {
            const items = [];
            items.push({ label: `Role: ${a.role || 'none'}` });
            if (a.instructions) items.push({ label: `Instructions: ${a.instructions}` });
            items.push({ label: `Model: ${(agent_config[a.name] || {}).model || 'opus'}` });
            items.push({ label: `Directory: ${AGENT_DIRS_CLIENT[a.name] || 'unknown'}` });
            showBottomSheet('Details — ' + a.name, items, () => {});
          }
        });
      };
    }
```

- [ ] **Step 3: Also update the Gurvinder card for mobile**

After the gurvinder card HTML, add mobile overlay:

Find:
```javascript
  gCard.onclick = () => { $target.value = 'all'; $input.focus(); };
```

Insert BEFORE it:
```javascript
  const gMobileHtml = `
    <div class="mobile-card-body">
      <div class="mobile-card-info">
        <div class="mobile-card-name" style="color:${gColor}">gurvinder</div>
        <div class="mobile-card-role">Operator</div>
      </div>
      <div class="mobile-card-status">
        <div class="mobile-status-row">
          <span class="mobile-status-dot active"></span>
          <span class="mobile-status-word active">online</span>
        </div>
      </div>
    </div>
  `;
  gCard.insertAdjacentHTML('beforeend', gMobileHtml);
```

- [ ] **Step 4: Add avatar circles to cards (both desktop and mobile)**

The avatar circle needs to be the first child of each card. On desktop it's 28px, on mobile it's 40px. We render it at the card level (before `ac-row1`).

For the gurvinder card, find the line where `gCard.innerHTML = ...` is set. Prepend the avatar:

Change `gCard.innerHTML` to start with the avatar:
```javascript
  gCard.innerHTML = `
    ${renderAvatarCircle({name: 'gurvinder'}, 28)}
    <div class="ac-row1">
```

Wait — this breaks the desktop layout because ac-row1 needs to be the flex container. Better approach: add a CSS rule that makes `.ac` a flex row on mobile with the avatar as the first item, and on desktop the avatar sits inside `ac-row1`.

Actually, the simplest approach: insert the avatar circle as the FIRST child of the card, and on mobile CSS `.ac` is already `display: flex; align-items: center; gap: 12px`. On desktop, `.ac` is block layout so the avatar will stack vertically — we need to make desktop `.ac-row1` include the avatar.

Let me revise: insert the avatar into `ac-row1` on desktop (already done in step 2 of Task 3), and on mobile the CSS hides `ac-row1` contents except the avatar. Actually, the mobile CSS already hides `ac-row1` children. The avatar needs to be at the card level for mobile.

The cleanest approach: render the avatar as a direct child of the card element (outside `ac-row1`), and on desktop position it absolutely or float it. On mobile, the card is `display: flex` and the avatar is the first flex child.

On desktop, add CSS:
```css
  .ac > .agent-avatar { display: none; } /* Desktop: avatar is inside ac-row1 */
```

On mobile, add CSS:
```css
  .ac > .agent-avatar { display: flex; } /* Mobile: avatar is a direct card child */
  .ac .ac-row1 .agent-avatar { display: none; } /* Hide desktop avatar on mobile */
```

Add the avatar to each card's innerHTML at the top level. For active agents, after `card.innerHTML = ...`, prepend:

Actually — let me simplify. Just add the avatar as a direct child element prepended to the card, and use CSS to show/hide based on context.

For the gurvinder card, after setting `gCard.innerHTML`, prepend avatar:
```javascript
  gCard.insertAdjacentHTML('afterbegin', renderAvatarCircle({name: 'gurvinder'}, 40));
```

For active agents, after setting `card.innerHTML`, prepend avatar:
```javascript
  card.insertAdjacentHTML('afterbegin', renderAvatarCircle(a, 40));
```

Then in CSS:
```css
/* Desktop: hide card-level avatar (desktop uses the one inside ac-row1) */
.ac > .agent-avatar { display: none; }
```

And in mobile CSS:
```css
/* Mobile: show card-level avatar, hide ac-row1 avatar */
.ac > .agent-avatar { display: flex; }
.ac .ac-row1 .agent-avatar { display: none; }
```

- [ ] **Step 5: Commit**

```bash
git add static/index.html
git commit -m "feat(m2): step 5 — mobile agent cards with avatars, bottom sheet actions"
```

---

### Task 6: Final Verification + Push

**Files:**
- No modifications — verification only

- [ ] **Step 1: Restart server**

```bash
cd ~/coders-war-room && bash restart-server.sh
```

- [ ] **Step 2: Verify API returns color/icon fields**

```bash
curl -s http://localhost:5680/api/agents | python3 -c "
import sys,json
for a in json.load(sys.stdin):
    print(f'{a[\"name\"]:15s} color={str(a.get(\"color\",\"None\")):10s} icon={a.get(\"icon\",\"None\")}')
"
```

- [ ] **Step 3: Verify desktop is not broken**

Open http://localhost:5680 in a desktop browser. Verify:
- Agent cards show small avatar circles (28px)
- Agent names are colored per role
- Creation form shows color and icon pickers
- All existing functionality works (messaging, file browser, agent actions)

- [ ] **Step 4: Push**

```bash
git push origin main
```

- [ ] **Step 5: Screenshot request**

Ask Gurvinder to screenshot the mobile Agents tab on iPhone.

---

## Success Criteria Checklist

| # | Criterion | Task |
|---|-----------|------|
| 1 | Each agent has a colored circular avatar | Task 2, 3, 5 |
| 2 | Color defaults match role type | Task 1, 2 |
| 3 | Color/icon selectable during creation | Task 4 |
| 4 | Color/icon persist across restarts | Task 1 |
| 5 | Mobile cards: avatar, name, role, presence | Task 5 |
| 6 | Mobile tap opens action bottom sheet | Task 5 |
| 7 | Agent list ordered by presence | Task 5 |
| 8 | Offline agents dimmed | Task 5 |
| 9 | Desktop layout additive only | Task 3, 4 |
| 10 | Zero regressions | All tasks |
