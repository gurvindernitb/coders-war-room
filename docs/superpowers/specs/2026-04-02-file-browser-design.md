# File Browser Right Panel — Design Spec

**Date:** 2026-04-02
**Goal:** Add a file browser panel to the right side of the War Room UI for browsing project files, seeing ownership at a glance, and drag-and-dropping files into chat to assign work to agents.
**Principle:** Browse in the web UI, read in Warp. The file browser is for referencing and assigning, not editing.

---

## Problem

When coordinating across agents, the user needs to reference specific files — "phase-3, look at composition.py" or "phase-1, fix the import in state.py." Currently this requires typing file paths from memory. There's no visual way to see the project structure, who owns which files, or quickly assign a file to an agent.

## Solution

A right-side panel showing the project directory tree with agent ownership as colored dots. Files can be dragged to the chat input (inserts path as text) or dragged to an agent card (auto-composes a targeted message with the file path).

---

## Layout

Three-column layout:

```
┌──────────┬────────────────────┬───────────┐
│  Agents  │       Chat         │   Files   │
│  300px   │      flex          │   280px   │
└──────────┴────────────────────┴───────────┘
```

The file panel has:
- Header: "FILES" label + current project path
- Tree: single root directory tree, collapsible folders
- No tabs, no modes — just the tree

---

## File Tree

### Data Source

`GET /api/files?path=<dir>` returns entries for a directory:

```json
{
  "current": "/Users/gurvindersingh/contextualise/northstar",
  "parent": "/Users/gurvindersingh/contextualise",
  "entries": [
    {"name": "state.py", "type": "file", "path": "northstar/state.py", "owner": "phase-1", "color": "#448aff"},
    {"name": "heartbeat.py", "type": "file", "path": "northstar/heartbeat.py", "owner": "phase-3", "color": "#ff80ab"},
    {"name": "tools", "type": "dir", "path": "northstar/tools", "has_owned": true},
    {"name": "config", "type": "dir", "path": "northstar/config", "has_owned": false},
    {"name": "README.md", "type": "file", "path": "northstar/README.md", "owner": null, "color": null}
  ]
}
```

### Rules

- Rooted at the project directory from `config.yaml` (`project_path`)
- Directories listed first, then files. Both alphabetically sorted.
- Hidden files/dirs excluded (starting with `.`) except `.claude`
- Each file entry includes `owner` (agent name or null) and `color` (agent's hex color or null)
- Each directory entry includes `has_owned` (boolean) — true if any descendant file is owned by an agent
- Ownership resolved by matching file's relative path against all agents' `owns` glob patterns

### Rendering

- **Folders**: `▸ foldername` (collapsed) / `▾ foldername` (expanded). Click to toggle.
- **Files**: `  filename` with colored dot if owned. Dim text if unowned.
- **Owned file**: `● state.py` where ● is colored to match the owning agent (e.g., phase-1's blue)
- **Unowned file**: `  README.md` in dim text, no dot
- **Indent**: 16px per nesting level

### Auto-Expand on Load

On initial load, the tree auto-expands folders where `has_owned: true`. This reveals all owned files without the user clicking. Folders with no owned descendants stay collapsed.

The tree is loaded lazily — each folder's contents fetched on expand (or auto-expand). Only the root is fetched on page load.

---

## Interactions

### Click File → Open in Warp

Clicking a file name opens it in Warp with syntax highlighting:

1. `POST /api/files/open` with `{"path": "northstar/state.py"}`
2. Server creates a launcher script: `bat --paging=always <full_path>` (falls back to `less`)
3. Opens via `open -a Warp <launcher>`

### Drag File to Chat Input

HTML5 drag-and-drop:

1. File tree items have `draggable="true"`
2. On `dragstart`, set `dataTransfer` with the file's relative path
3. Chat input textarea has `dragover` (prevent default) and `drop` handlers
4. On drop, insert the relative path at cursor position: `northstar/state.py`
5. User types their instruction and sends

Result message: `@phase-1 review northstar/state.py for import issues`

### Drag File to Agent Card

1. Agent cards in the sidebar accept drops (class `ac` gets `dragover`/`drop` handlers)
2. On drop:
   - Set the @target dropdown to the agent's name
   - Insert `[file: northstar/state.py] ` in the chat input
   - Focus the input for the user to type their instruction
3. User types instruction and sends

Result message: `[WARROOM @phase-1] gurvinder: [file: northstar/state.py] review for import issues`

---

## API

### `GET /api/files?path=<relative_path>`

Lists directory contents with ownership info.

**Default**: `path=.` (project root)

**Response**: see File Tree section above.

**Server-side**:
1. Resolve path relative to `PROJECT_PATH`
2. Security: must be under `PROJECT_PATH` (no path traversal)
3. List directory entries (dirs first, then files, alphabetical)
4. For each file: check against all agents' `owns` patterns using `fnmatch` on relative path
5. For each dir: recursively check if any descendant matches any `owns` pattern (cache this at startup)
6. Exclude hidden entries except `.claude`

### `POST /api/files/open`

Opens a file in Warp with syntax highlighting.

**Request**: `{"path": "northstar/state.py"}`

**Server-side**:
1. Resolve full path
2. Security: must be under `PROJECT_PATH`
3. Create launcher script with `bat` (or `less` fallback)
4. `open -a Warp <launcher>`

---

## Ownership Resolution

At startup, the server pre-computes which directories contain owned files:

```python
# For each agent's owns patterns, resolve to actual file paths
# For each resolved file, mark all ancestor directories as "has_owned"
# Store in a dict: dir_has_owned[relative_dir_path] = True
```

This makes the `has_owned` field O(1) per directory listing, not a recursive scan.

For file ownership: `fnmatch.fnmatch(relative_path, pattern)` against each agent's patterns. First match wins (files can only have one owner).

---

## Visual Style

Matches existing War Room aesthetic:

- Background: `var(--bg-deep)` (same as agent sidebar)
- Border-left: `1px solid var(--border)`
- Font: JetBrains Mono, 11px for filenames
- Folder icons: `▸`/`▾` in `var(--text-dim)`
- Owned file dot: 6px circle, agent's color, subtle glow
- Unowned file: `var(--text-dim)` color
- Hover: `var(--bg-card-hover)` background
- Drag active: file item gets a subtle border highlight
- Drop target (chat input): blue border glow when file is dragged over
- Drop target (agent card): agent's color border glow when file is dragged over

---

## What This Does NOT Include

- No file content preview in the web UI (use Warp/cli button)
- No file editing
- No file upload
- No multi-file drag (one at a time, keep it simple)
- No search/filter within the tree (future enhancement)
- No git status indicators on files (future enhancement, per git-agent's suggestion)
- No file creation or deletion
