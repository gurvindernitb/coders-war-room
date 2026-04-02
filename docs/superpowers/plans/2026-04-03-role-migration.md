# Package E: Role-Based Migration — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Migrate the War Room from phase-based to role-based agents — rewrite startup/onboarding files, add role presets to the web UI, remove ownership infrastructure, update all references.

**Architecture:** Config.yaml already updated with 7 role-based agents. This plan rewrites the onboarding pipeline (startup.md, onboarding-prompt.md, onboard.sh, join.sh), adds role presets to the web UI form, removes server-side ownership code, and cleans up the frontend and tests.

**Tech Stack:** Python 3.12, FastAPI, Bash, vanilla JS

**Design Spec:** `docs/superpowers/specs/2026-04-03-role-migration-design.md`

---

## File Structure

| File | Action | What changes |
|------|--------|-------------|
| `config.yaml` | Modify | Add `instructions` and `role_type` fields, review all values |
| `startup.md` | Rewrite | Universal pipeline protocol (no phase references) |
| `onboarding-prompt.md` | Rewrite | Role-based template with instructions file placeholder |
| `onboard.sh` | Modify | Read `instructions`/`role_type` from config, inject into template |
| `join.sh` | Modify | Show instructions file path on join |
| `server.py` | Modify | Remove ownership code, remove /owns endpoint, clean up status push and files API |
| `static/index.html` | Modify | Remove ownership pills/dots, update shortRole, add role presets to onboarding form |
| `tests/test_api.py` | Modify | Remove ownership tests, update file listing tests |
| `tests/test_integration.py` | Modify | Remove ownership integration tests |
| `tests/conftest.py` | Modify | Remove ownership patches |

---

### Task 1: Config, Startup, and Onboarding Files

**Files:**
- Modify: `~/coders-war-room/config.yaml`
- Rewrite: `~/coders-war-room/startup.md`
- Rewrite: `~/coders-war-room/onboarding-prompt.md`

- [ ] **Step 1: Update config.yaml — add instructions and role_type fields**

Review the existing config.yaml (modified by someone else) and add `instructions` and `role_type` fields. Verify all role descriptions match the documentation at `~/Desktop/contextualise-docs/`.

The final config.yaml should be:

```yaml
# Coders War Room — Agent Configuration
# Updated: 2026-04-03
# Model: Six-role pipeline (replaces phase-based model)

port: 5680
project_path: ~/contextualise

agents:
  - name: supervisor
    role: "Strategic brain. Reads Jira, decomposes work into task briefs using Sequential Thinking, assigns to pipeline agents, reviews QA reports, approves merges, maintains context-spec.yaml and PROJECT_STATUS.md. Never writes code."
    tmux_session: warroom-supervisor
    auto_onboard: false
    role_type: supervisor
    instructions: SUPERVISOR_INSTRUCTIONS.md
    owns: []

  - name: scout
    role: "Research and investigation. Analyses code, maps blast radius, verifies dependencies (slopsquatting defence), produces research ledgers at docs/research/. Works ahead of Engineers — always researching the next task. Never writes code."
    tmux_session: warroom-scout
    role_type: scout
    instructions: SCOUT_INSTRUCTIONS.md
    owns: []

  - name: engineer-1
    role: "Implementation. Receives task brief + research ledger, works in isolated git worktree, follows Superpowers TDD workflow, produces tested code on feature branches. May run in parallel with engineer-2 on independent tasks."
    tmux_session: warroom-engineer-1
    role_type: engineer
    instructions: ENGINEER_INSTRUCTIONS.md
    owns: []

  - name: engineer-2
    role: "Implementation (parallel). Same as engineer-1 but for independent concurrent tasks. Only activated when the Supervisor assigns parallel work. Operates in a separate worktree."
    tmux_session: warroom-engineer-2
    role_type: engineer
    instructions: ENGINEER_INSTRUCTIONS.md
    owns: []

  - name: qa
    role: "Quality gate. Runs full verification suite (pytest, flake8, mypy, bandit) plus blast radius checks. Produces QA reports at docs/qa/. Verdict is PASS or FAIL with evidence — no soft passes. Never writes code."
    tmux_session: warroom-qa
    role_type: qa
    instructions: QA_INSTRUCTIONS.md
    owns: []

  - name: git-agent
    role: "Persistence backbone. Handles all git operations: commits, branches, merges, cleanup. Activated at six commit points per task lifecycle. Runs test gate before every merge to main. Never writes code. Never merges without Supervisor approval. Never force-pushes without Gurvinder's direct confirmation."
    tmux_session: warroom-git-agent
    role_type: git-agent
    instructions: GIT_AGENT_INSTRUCTIONS.md
    owns: []

  - name: chronicler
    role: "Silent observer. Reads War Room history, research ledgers, QA reports, and git log. Produces weekly learnings reports at docs/chronicler/. Detects spec drift, regression patterns, tool usage, and process friction. Proposes guardrail revisions. Never participates in the active pipeline."
    tmux_session: warroom-chronicler
    role_type: chronicler
    instructions: CHRONICLER_INSTRUCTIONS.md
    owns: []
```

- [ ] **Step 2: Rewrite startup.md**

Replace `~/coders-war-room/startup.md` entirely:

```markdown
# War Room — Agent Startup Protocol

You are an agent in the Coder's War Room for Project Contextualise. This file covers the universal protocol that ALL agents follow. Your role-specific instructions are in a separate file — you'll be told which one to read.

## Communication

### Message Protocol
- `[WARROOM @your-name]` — directed at you. You MUST respond and act.
- `[WARROOM]` — broadcast. Respond only if it directly impacts your current work. Otherwise say "Noted" in the terminal. Do NOT post acknowledgements to the war room.
- `[WARROOM SYSTEM]` — informational. Do not respond.

### Commands
```
~/coders-war-room/warroom.sh post "message"              # broadcast
~/coders-war-room/warroom.sh post --to <agent> "message"  # direct message
~/coders-war-room/warroom.sh history                      # recent messages
~/coders-war-room/warroom.sh mentions                     # messages for you
~/coders-war-room/warroom.sh status "task" --progress N   # update your card
~/coders-war-room/warroom.sh roll-call                    # check who's alive
```

### When to Post
- **Immediately:** Blocker, need file outside scope, cross-agent conflict, security issue, stall >10 minutes
- **On completion:** Task done, evidence attached
- **On failure:** What broke, what you tried
- **Never:** Status updates for the sake of updates (silence = working)

### @Mentions Are Mandatory
- `@git-agent commit <filepath>` — request a commit
- `@git-agent merge approved for <STORY-ID>` — request a merge
- `@supervisor` — escalate a decision or request approval
- `@scout` — request investigation
- Tags are explicit — agents do not monitor for implicit signals.

## The Six Commit Points

Every task that moves through the pipeline generates up to six Git commits:

1. **Scout Research** — `@git-agent commit docs/research/<STORY-ID>_notes.md`
2. **Working Notes** (if context >80%) — `@git-agent commit docs/research/<STORY-ID>_working.md`
3. **Engineer Code** — `@git-agent commit and push feature/<STORY-ID>`
4. **QA Report** — `@git-agent commit docs/qa/<STORY-ID>_review.md`
5. **Merge to Main** — `@git-agent merge approved for <STORY-ID>` (Supervisor only)
6. **Status Update** — `@git-agent commit docs/PROJECT_STATUS.md` (Supervisor only)

## Escalation Rules

- **90%+ confident:** Proceed. Log your decision.
- **60-89% confident:** Proceed with caution, flag to Supervisor in War Room.
- **Below 60%:** Stop. Post to War Room. Wait for Supervisor or Gurvinder.

### Immediate Escalation (Never Self-Resolve)
- Cross-agent conflict
- Security vulnerability discovered
- Data contract change needed (DB schema, config shape, API)
- New dependency required
- Change to shared resources (context-spec.yaml, compile.py, entities.yaml)
- Goal drift detected
- Stall (stuck >10 minutes with no progress)

## Git Rules

All git operations go through the git-agent. Never run destructive git commands (push, reset, rebase, merge) directly. Post to the war room with `@git-agent` and wait for confirmation.

## Session End

When your work is done:
1. Ensure all artifacts are committed via git-agent
2. Post completion summary to the war room
3. Terminate cleanly (fresh context is better than stale)
```

- [ ] **Step 3: Rewrite onboarding-prompt.md**

Replace `~/coders-war-room/onboarding-prompt.md` entirely:

```markdown
# War Room Onboarding

You are **{{AGENT_NAME}}** in the Coder's War Room — a role-based pipeline for Project Contextualise.

**Your role:** {{AGENT_ROLE}}
**Your role type:** {{ROLE_TYPE}}

---

## Startup Sequence

Complete these steps in order:

### Step 1: Read your operating manuals
1. Read `~/coders-war-room/startup.md` — war room protocol and communication rules
2. Read `~/contextualise/docs/{{INSTRUCTIONS_FILE}}` — your complete role-specific operating manual
3. Read `~/contextualise/CLAUDE.md` — project context and constitution

### Step 2: Check the war room
```bash
~/coders-war-room/warroom.sh history
```
Look for any messages directed at you (`@{{AGENT_NAME}}`).

### Step 3: Announce yourself
```bash
~/coders-war-room/warroom.sh post "{{AGENT_NAME}} onboarded. Role: {{ROLE_TYPE}}. Instructions read. Ready for directives."
```

### Step 4: Wait for instructions
Do NOT start work until you receive a directive from the Supervisor or Gurvinder.
```

- [ ] **Step 4: Commit**

```bash
cd ~/coders-war-room
git add config.yaml startup.md onboarding-prompt.md
git commit -m "feat: rewrite config, startup, and onboarding for role-based pipeline"
```

---

### Task 2: onboard.sh and join.sh — Template Variable Updates

**Files:**
- Modify: `~/coders-war-room/onboard.sh`
- Modify: `~/coders-war-room/join.sh`

- [ ] **Step 1: Update get_agents() in onboard.sh to output instructions and role_type**

Find the `get_agents()` function in onboard.sh. Currently it outputs `name|tmux_session|role`. Change the Python code inside it to also output `instructions` and `role_type`:

```python
for a in agents:
    if not filter_names or a['name'] in filter_names:
        instr = a.get('instructions', 'startup.md')
        rtype = a.get('role_type', a['name'])
        print(f\"{a['name']}|{a['tmux_session']}|{a['role']}|{instr}|{rtype}\")
```

- [ ] **Step 2: Update the while-read loop to capture new fields**

Change:
```bash
while IFS='|' read -r name session role; do
    onboard_agent "$name" "$session" "$role"
done
```
To:
```bash
while IFS='|' read -r name session role instructions role_type; do
    onboard_agent "$name" "$session" "$role" "$instructions" "$role_type"
done
```

- [ ] **Step 3: Update onboard_agent() to accept and use new parameters**

Change the function signature from:
```bash
onboard_agent() {
    local name="$1"
    local session="$2"
    local role="$3"
```
To:
```bash
onboard_agent() {
    local name="$1"
    local session="$2"
    local role="$3"
    local instructions="${4:-startup.md}"
    local role_type="${5:-$name}"
```

- [ ] **Step 4: Update the sed command to include new placeholders**

Change the template substitution from:
```bash
sed "s/{{AGENT_NAME}}/$name/g; s|{{AGENT_ROLE}}|$role|g" "$template_file" > "$onboard_file"
```
To:
```bash
sed "s/{{AGENT_NAME}}/$name/g; s|{{AGENT_ROLE}}|$role|g; s/{{INSTRUCTIONS_FILE}}/$instructions/g; s/{{ROLE_TYPE}}/$role_type/g" "$template_file" > "$onboard_file"
```

- [ ] **Step 5: Update the injection message**

Change the tmux injection from referencing "4 steps" and "4 core files" to:
```bash
tmux set-buffer -b warroom-onboard "Read the onboarding instructions at $onboard_file and follow the startup sequence. Start with Step 1: read your operating manuals."
```

- [ ] **Step 6: Update join.sh to show instructions file**

In join.sh, find the protocol output (the `cat << EOF` block) and update to include the instructions file:

```bash
# Fetch role and instructions from server
AGENT_INFO=$(curl -s "$SERVER_URL/api/agents" 2>/dev/null | python3 -c "
import sys, json
try:
    agents = json.load(sys.stdin)
    match = [a for a in agents if a['name'] == '$AGENT_NAME']
    if match:
        a = match[0]
        print(f\"{a.get('role', 'Agent')}|{a.get('instructions', 'startup.md')}|{a.get('role_type', '$AGENT_NAME')}\")
    else:
        print('Agent|startup.md|$AGENT_NAME')
except: print('Agent|startup.md|$AGENT_NAME')
" 2>/dev/null || echo "Agent|startup.md|$AGENT_NAME")

ROLE=$(echo "$AGENT_INFO" | cut -d'|' -f1)
INSTRUCTIONS=$(echo "$AGENT_INFO" | cut -d'|' -f2)
ROLE_TYPE=$(echo "$AGENT_INFO" | cut -d'|' -f3)
```

And update the output block:
```bash
cat << EOF

======================================
  JOINED: $AGENT_NAME
  ROLE TYPE: $ROLE_TYPE
  INSTRUCTIONS: ~/contextualise/docs/$INSTRUCTIONS
======================================

STARTUP:
  1. Read ~/coders-war-room/startup.md
  2. Read ~/contextualise/docs/$INSTRUCTIONS
  3. Read ~/contextualise/CLAUDE.md
  4. Run: ~/coders-war-room/warroom.sh history

WAR ROOM COMMANDS:
  ~/coders-war-room/warroom.sh post "message"
  ~/coders-war-room/warroom.sh post --to <agent> "message"
  ~/coders-war-room/warroom.sh history

PROTOCOL:
  [WARROOM @$AGENT_NAME] = directed at you, MUST act
  [WARROOM] = broadcast, respond only if relevant
  [WARROOM SYSTEM] = info only, ignore

EOF
```

- [ ] **Step 7: Commit**

```bash
cd ~/coders-war-room
git add onboard.sh join.sh
git commit -m "feat: onboard.sh and join.sh support role_type and instructions fields"
```

---

### Task 3: Server — Remove Ownership Infrastructure

**Files:**
- Modify: `~/coders-war-room/server.py`

- [ ] **Step 1: Remove ownership imports and data structures**

Remove `import fnmatch` (line 2).

Remove these data structures (around lines 73, 109):
- `agent_owns_resolved: dict[str, list[str]] = {}`
- `dir_has_owned: dict[str, bool] = {}`

- [ ] **Step 2: Remove ownership functions**

Remove these functions entirely:
- `resolve_ownership()` (line 93-106)
- `precompute_dir_ownership()` (line 112-126)
- `get_file_owner()` (line 129-134)
- `refresh_last_commits()` — keep this function but remove the `owns` pattern-based file lookup. Change it to track commits per agent based on the project-wide git log, not owned files. Simplify to just get the latest commit in the project:

```python
def refresh_last_commits():
    """Get the latest commit in the project directory."""
    try:
        result = subprocess.run(
            ["git", "-C", PROJECT_PATH, "log", "-1", "--format=%h %s"],
            capture_output=True, text=True, timeout=5,
        )
        if result.returncode == 0 and result.stdout.strip():
            parts = result.stdout.strip().split(" ", 1)
            commit = {"hash": parts[0], "message": parts[1] if len(parts) > 1 else ""}
            # Set for all agents (project-wide last commit)
            for a in AGENTS:
                agent_last_commit[a["name"]] = commit
    except (subprocess.TimeoutExpired, FileNotFoundError):
        pass
```

- [ ] **Step 3: Remove owns from agent_status_loop**

In the `agent_status_loop` function, remove:
```python
            owns = agent_owns_resolved.get(name, [])
```
and remove `"owns": owns,` from the `agents_data[name]` dict.

- [ ] **Step 4: Remove /api/agents/{name}/owns endpoint**

Remove the entire `get_agent_owns` function (around line 959).

- [ ] **Step 5: Remove owns from /api/agents response**

In the `list_agents` function, remove any `owns` field from the response dict.

- [ ] **Step 6: Update /api/files endpoint**

Remove ownership from file entries. Change the file entry from:
```python
owner, color = get_file_owner(rel_path)
entries.append({"name": name, "type": "file", "path": rel_path, "owner": owner, "color": color})
```
To:
```python
entries.append({"name": name, "type": "file", "path": rel_path})
```

Change directory entries from:
```python
entries.append({"name": name, "type": "dir", "path": rel_path, "has_owned": dir_has_owned.get(rel_path, False)})
```
To:
```python
entries.append({"name": name, "type": "dir", "path": rel_path})
```

- [ ] **Step 7: Remove ownership calls from lifespan**

Remove these lines from the `lifespan` function:
```python
    resolve_ownership()
    precompute_dir_ownership()
```

- [ ] **Step 8: Add instructions and role_type to /api/agents response**

In the `list_agents` function, add:
```python
            "instructions": a.get("instructions", ""),
            "role_type": a.get("role_type", a["name"]),
```

- [ ] **Step 9: Store instructions and role_type in create_agent()**

In the `create_agent` endpoint, when building `agent_entry`, add:
```python
            "instructions": req.instructions if hasattr(req, 'instructions') else "",
            "role_type": req.role_type if hasattr(req, 'role_type') else req.name,
```

Update the `AgentCreate` Pydantic model to include:
```python
    instructions: str = ""
    role_type: str = ""
```

- [ ] **Step 10: Run existing tests (some will fail — expected)**

```bash
cd ~/coders-war-room
python3 -m pytest tests/test_api.py -v 2>&1 | tail -15
```

Some ownership tests will fail. That's expected — we fix them in Task 5.

- [ ] **Step 11: Commit**

```bash
cd ~/coders-war-room
git add server.py
git commit -m "feat: remove ownership infrastructure, add instructions/role_type to agent API"
```

---

### Task 4: Frontend — Remove Ownership UI + Update Role Map + Role Presets

**Files:**
- Modify: `~/coders-war-room/static/index.html`

- [ ] **Step 1: Update shortRole() and ROLE_MAP**

Replace the current ROLE_MAP and shortRole function:

```javascript
const ROLE_MAP = {
  'supervisor': 'Coordinator',
  'scout': 'Research',
  'engineer-1': 'Engineer',
  'engineer-2': 'Engineer',
  'qa': 'Quality Gate',
  'git-agent': 'Git Ops',
  'chronicler': 'Observer',
};

function shortRole(role, name) {
  if (!role) return '';
  if (ROLE_MAP[name]) return ROLE_MAP[name];
  // For dynamic agents, try to extract a short label
  return role.length > 24 ? role.slice(0, 24) + '...' : role;
}
```

- [ ] **Step 2: Remove owned files pills from agent cards**

In the `renderAgents()` function's `activeAgents.forEach` block, remove:
- The `owns` variable extraction: `const owns = d.owns || [];`
- The `ownsHtml` construction block (the one with `ac-own-pill`)
- The `${ownsHtml}` from the card innerHTML

- [ ] **Step 3: Remove ownership dots from file browser**

In the `loadDir()` function, change the file item rendering from:
```javascript
const dot = entry.color
  ? `<span class="fp-dot" style="background:${entry.color};box-shadow:0 0 4px ${entry.color}44" title="${esc(entry.owner)}"></span>`
  : '<span style="width:6px"></span>';
item.innerHTML = `${dot}<span class="fp-name">${esc(entry.name)}</span>`;
```
To:
```javascript
item.innerHTML = `<span class="fp-name">${esc(entry.name)}</span>`;
```

And change file item class from varying `owned` to just:
```javascript
item.className = 'fp-item file';
```

- [ ] **Step 4: Update auto-expand logic in file browser**

Change the auto-expand logic from `entry.has_owned` to expanding the first level by default:

```javascript
const isExpanded = autoExpand && depth === 0;
```

This auto-expands all top-level directories on first load (since we no longer have ownership to guide expansion).

- [ ] **Step 5: Remove unused CSS**

Remove these CSS blocks:
- `.ac-owns` and children (`ac-own-pill`, `ac-own-more`)
- `.fp-dot`
- `.fp-item.file.owned`

- [ ] **Step 6: Add role presets to the New Agent drawer**

In the drawer JavaScript, add a role presets object:

```javascript
const ROLE_PRESETS = {
  supervisor: {
    role: "Strategic brain. Reads Jira, decomposes work into task briefs using Sequential Thinking, assigns to pipeline agents, reviews QA reports, approves merges. Never writes code.",
    instructions: "SUPERVISOR_INSTRUCTIONS.md",
    prompt: "Startup: Read docs/PROJECT_STATUS.md for handoff context. Check Jira for current sprint state. Assess what's in each pipeline stage.",
  },
  scout: {
    role: "Research and investigation. Analyses code, maps blast radius, verifies dependencies, produces research ledgers at docs/research/. Works ahead of Engineers. Never writes code.",
    instructions: "SCOUT_INSTRUCTIONS.md",
    prompt: "Startup: Check Jira 'Scout Review' column for assignments. Read the story description. Begin research.",
  },
  engineer: {
    role: "Implementation. Receives task brief + research ledger, works in isolated git worktree, follows Superpowers TDD workflow, produces tested code on feature branches.",
    instructions: "ENGINEER_INSTRUCTIONS.md",
    prompt: "Startup: Read the task brief from Supervisor. Read the research ledger at docs/research/<STORY-ID>_notes.md. Set up your worktree.",
  },
  qa: {
    role: "Quality gate. Runs full verification suite (pytest, flake8, mypy, bandit). Produces QA reports at docs/qa/. Verdict is PASS or FAIL with evidence. Never writes code.",
    instructions: "QA_INSTRUCTIONS.md",
    prompt: "Startup: Check Jira 'QA Review' column. Checkout the feature branch. Run the full verification suite.",
  },
  'git-agent': {
    role: "Persistence backbone. All git operations: commits, branches, merges, cleanup. Six commit points per task. Runs test gate before merge. Never writes code. Never merges without Supervisor approval.",
    instructions: "GIT_AGENT_INSTRUCTIONS.md",
    prompt: "Startup: Check for pending commit requests in the war room. Verify branch state with git status.",
  },
  chronicler: {
    role: "Silent observer. Reads War Room, research ledgers, QA reports, git log. Produces weekly learnings at docs/chronicler/. Detects spec drift and regression patterns. Never participates in active pipeline.",
    instructions: "CHRONICLER_INSTRUCTIONS.md",
    prompt: "Startup: Read war room history. Check recent git log. Review latest QA reports.",
  },
};
```

- [ ] **Step 7: Change the role text input to a dropdown + free text**

In the drawer HTML, replace the role text input with:

```html
<label class="field-label">Role Type</label>
<select id="fRoleType" class="field-select">
  <option value="">Select a role...</option>
  <option value="supervisor">Supervisor</option>
  <option value="scout">Scout</option>
  <option value="engineer">Engineer</option>
  <option value="qa">QA</option>
  <option value="git-agent">Git Agent</option>
  <option value="chronicler">Chronicler</option>
  <option value="other">Other (custom)</option>
</select>

<label class="field-label">Role Description</label>
<textarea id="fRole" class="field-textarea" rows="2" placeholder="Auto-filled from role type, or type custom..."></textarea>
```

- [ ] **Step 8: Add role type change handler**

```javascript
$('fRoleType').onchange = () => {
  const rt = $('fRoleType').value;
  const preset = ROLE_PRESETS[rt];
  if (preset) {
    $('fRole').value = preset.role;
    $('fPrompt').value = preset.prompt;
  } else if (rt === 'other') {
    $('fRole').value = '';
    $('fPrompt').value = '';
  }
};
```

- [ ] **Step 9: Update the create agent fetch to include role_type and instructions**

In the create button click handler, add role_type and instructions to the POST body:

```javascript
const roleType = $('fRoleType').value || 'other';
const preset = ROLE_PRESETS[roleType];
const instructions = preset ? preset.instructions : '';

body: JSON.stringify({
  name,
  directory: selectedDir,
  role: $('fRole').value.trim(),
  initial_prompt: $('fPrompt').value,
  model: $('fModel').value,
  skip_permissions: $('fPerms').checked,
  role_type: roleType,
  instructions: instructions,
}),
```

- [ ] **Step 10: Commit**

```bash
cd ~/coders-war-room
git add static/index.html
git commit -m "feat: role presets in onboard form, remove ownership UI, update role map"
```

---

### Task 5: Tests — Remove Ownership Tests + Fix Remaining

**Files:**
- Modify: `~/coders-war-room/tests/test_api.py`
- Modify: `~/coders-war-room/tests/test_integration.py`
- Modify: `~/coders-war-room/tests/conftest.py`

- [ ] **Step 1: Remove ownership tests from test_api.py**

Remove these test functions:
- `test_get_agent_owns` (around line 227)
- `test_list_files_with_ownership` (around line 270)
- `test_list_files_dirs_have_owned` (around line 289)

- [ ] **Step 2: Update test_list_files_root**

Update the test to NOT check for `owner` or `color` fields. Just verify `name`, `type`, `path`:

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
        for e in data["entries"]:
            assert "name" in e
            assert "type" in e
            assert "path" in e
```

- [ ] **Step 3: Remove ownership integration tests**

In test_integration.py, remove:
- `test_ownership_api` (around line 220)
- `test_files_ownership` (around line 242)

Update `test_files_api` to not check `has_owned`:

```python
def test_files_api():
    """Test the files listing endpoint."""
    resp = httpx.get(f"{SERVER_URL}/api/files?path=.")
    assert resp.status_code == 200
    data = resp.json()
    assert "entries" in data
    assert len(data["entries"]) > 0
```

- [ ] **Step 4: Remove ownership patches from conftest.py**

Remove these lines:
```python
    monkeypatch.setattr(server, "dir_has_owned", {})
```

Also remove the `agent_owns_resolved` patch if it exists.

- [ ] **Step 5: Run all tests**

```bash
cd ~/coders-war-room
python3 -m pytest tests/test_api.py tests/test_integration.py -v
```

Expected: All tests pass.

- [ ] **Step 6: Commit**

```bash
cd ~/coders-war-room
git add tests/test_api.py tests/test_integration.py tests/conftest.py
git commit -m "test: remove ownership tests, update file listing tests for role-based model"
```

---

### Task 6: Restart + End-to-End Verification

**Files:** None (verification only)

- [ ] **Step 1: Restart server**

```bash
cd ~/coders-war-room
pkill -f "python3.*server.py" 2>/dev/null; sleep 1
python3 server.py &
sleep 2
```

- [ ] **Step 2: Verify API returns role-based agents**

```bash
curl -s http://localhost:5680/api/agents | python3 -c "
import sys, json
agents = json.load(sys.stdin)
for a in agents:
    print(f\"{a['name']:15s} role_type={a.get('role_type','?'):12s} instructions={a.get('instructions','?')}\")
"
```

Expected: 7 agents with correct role_type and instructions fields.

- [ ] **Step 3: Verify file browser has no ownership dots**

```bash
curl -s "http://localhost:5680/api/files?path=northstar" | python3 -c "
import sys, json
data = json.load(sys.stdin)
files = [e for e in data['entries'] if e['type'] == 'file'][:3]
for f in files:
    keys = list(f.keys())
    print(f\"{f['name']:20s} keys={keys}\")
"
```

Expected: File entries have `name`, `type`, `path` — NO `owner` or `color`.

- [ ] **Step 4: Open web UI and verify**

```bash
open http://localhost:5680
```

Verify:
1. Sidebar shows role-based agent names (supervisor, scout, engineer-1, etc.)
2. Agent cards have NO owned files pills
3. File browser has NO colored ownership dots
4. Click "+ new" — role dropdown shows 7 presets
5. Select "Engineer" — role description and initial prompt auto-fill
6. shortRole shows "Coordinator", "Research", "Engineer", etc.

- [ ] **Step 5: Run full test suite**

```bash
cd ~/coders-war-room
python3 -m pytest tests/ -v
```

Expected: All tests pass.

- [ ] **Step 6: Final commit**

```bash
cd ~/coders-war-room
git add -A
git commit -m "feat: Package E complete — role-based migration verified end-to-end"
```
