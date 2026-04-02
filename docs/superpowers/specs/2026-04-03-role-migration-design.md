# Package E: Role-Based Migration — Design Spec

**Date:** 2026-04-03
**Goal:** Migrate the War Room from phase-based agents (phase-1 through phase-6) to role-based agents (supervisor, scout, engineer-1/2, qa, git-agent, chronicler) as defined by the new operational documentation.
**Scope:** Full migration except ownership dots in file browser (removed, not repurposed).

---

## What Changes

### 1. startup.md — Complete Rewrite

**Current:** References 4 phase-based core files (CLAUDE.md, QUALITY_STANDARDS.md, AGENT_PROTOCOL.md, northstar/CLAUDE.md), tells agents to explore owned files and check phase plans.

**New:** Universal war room protocol for the 6-role pipeline. No role-specific content — that lives in the instruction files.

**Contents:**
- War room communication protocol (@mentions, message prefixes, when to post)
- `warroom.sh` commands (post, history, mentions, status, roll-call)
- The 6 commit points summary (persistence protocol — what gets committed when)
- Escalation rules (confidence-based: 90%+ proceed, 60-89% flag, <60% stop)
- Immediate escalation triggers (cross-agent conflict, security, data contract, new dependency, stall >10min)
- Git rules: all git through git-agent, never direct commits, never force-push
- Session end protocol (commit work, post to war room, terminate cleanly)

**Does NOT contain:** Role-specific instructions, file ownership, phase references.

### 2. onboarding-prompt.md — Complete Rewrite

**Current:** Phase-based — references "what your role owns", "ownership table in AGENT_PROTOCOL.md", "relevant plan for your phase", "PLAN*_COMPLETE.md".

**New:** Role-based universal template with placeholders:

```markdown
# War Room Onboarding

You are **{{AGENT_NAME}}** in the Coder's War Room — a role-based pipeline for Project Contextualise.

**Your role:** {{AGENT_ROLE}}

## Startup Sequence

1. Read ~/coders-war-room/startup.md (war room protocol and communication rules)
2. Read ~/contextualise/docs/{{INSTRUCTIONS_FILE}} (your complete operating manual)
3. Read ~/contextualise/CLAUDE.md (project context and constitution)
4. Run: ~/coders-war-room/warroom.sh history (check for messages directed at you)

## After Reading

Post to the war room:
```
~/coders-war-room/warroom.sh post "{{AGENT_NAME}} onboarded. Role: {{ROLE_TYPE}}. Instructions read. Ready."
```

Then wait for instructions from the Supervisor or Gurvinder.

## War Room Commands

```
~/coders-war-room/warroom.sh post "message"
~/coders-war-room/warroom.sh post --to <agent> "message"
~/coders-war-room/warroom.sh history
~/coders-war-room/warroom.sh status "task description" --progress N --eta Nm
```
```

Placeholders `{{INSTRUCTIONS_FILE}}` and `{{ROLE_TYPE}}` are resolved from config.yaml's `instructions` field.

### 3. config.yaml — Add `instructions` field + thorough review

Add `instructions` field to each agent. Review all fields against documentation.

```yaml
  - name: engineer-1
    role: "Implementation. Receives task brief + research ledger..."
    tmux_session: warroom-engineer-1
    instructions: ENGINEER_INSTRUCTIONS.md
    role_type: engineer
    owns: []
```

The `role_type` field is the canonical role name (used in the onboarding prompt and the web UI dropdown). It differs from `name` for engineer-1/engineer-2 (both have `role_type: engineer`).

### 4. onboard.sh — Read instructions field from config

Currently uses `sed` to replace `{{AGENT_NAME}}` and `{{AGENT_ROLE}}` in the template. Must also replace:
- `{{INSTRUCTIONS_FILE}}` — from config.yaml `instructions` field
- `{{ROLE_TYPE}}` — from config.yaml `role_type` field

The `get_agents` function already parses config.yaml via Python. Add `instructions` and `role_type` to the pipe-delimited output.

### 5. join.sh — Update output

The brief protocol output on join currently works. Update to show the instructions file path so the agent knows where to look:

```
JOINED: engineer-1
ROLE: Implementation...
INSTRUCTIONS: ~/contextualise/docs/ENGINEER_INSTRUCTIONS.md
```

### 6. Web UI: Role Presets in New Agent Form

The onboarding drawer's role field becomes a dropdown with 7 options:

| Selection | Auto-fills: role | Auto-fills: instructions | Auto-fills: initial prompt |
|-----------|-----------------|------------------------|---------------------------|
| Supervisor | Full supervisor description | SUPERVISOR_INSTRUCTIONS.md | Startup: read Jira, check PROJECT_STATUS.md, assess pipeline |
| Scout | Full scout description | SCOUT_INSTRUCTIONS.md | Startup: check Jira "Scout Review" column, read story descriptions |
| Engineer | Full engineer description | ENGINEER_INSTRUCTIONS.md | Startup: read task brief, read research ledger, set up worktree |
| QA | Full QA description | QA_INSTRUCTIONS.md | Startup: check Jira "QA Review" column, checkout feature branch |
| Git Agent | Full git-agent description | GIT_AGENT_INSTRUCTIONS.md | Startup: check for pending commit requests, verify branch state |
| Chronicler | Full chronicler description | CHRONICLER_INSTRUCTIONS.md | Startup: read war room history, check recent git log |
| Other | (free text) | (free text) | (free text) |

The role descriptions and initial prompts are hardcoded in the frontend JavaScript from the documentation. Selecting a role fills everything; selecting "Other" clears to free text.

When creating the agent, the server stores `instructions` and `role_type` in the dynamic agent entry and `agent_config`.

### 7. Server — Remove Ownership Resolution

**Remove:**
- `agent_owns_resolved` dict
- `dir_has_owned` dict
- `resolve_ownership()` function
- `precompute_dir_ownership()` function
- `get_file_owner()` function
- `owns` field from `agent_status_loop` WebSocket push
- `owns` field from `/api/agents` response
- `GET /api/agents/{name}/owns` endpoint
- `precompute_dir_ownership()` call in lifespan
- `resolve_ownership()` call in lifespan
- Related imports (`fnmatch`)

**Keep:**
- `COLORS` dict (still used for agent name colors in sidebar/chat)
- `get_agent_color()` function (still used for dynamic agents)
- `last_commit` in status push (still useful — shows recent git activity per agent)
- `GET /api/files` endpoint (still useful for file browser, just without ownership data)

**Modify `/api/files` response:**
```json
{"name": "state.py", "type": "file", "path": "northstar/state.py"}
```
No more `owner` or `color` fields.

### 8. Frontend — Remove Ownership UI

**Sidebar cards:**
- Remove `ac-owns` pill section from `renderAgents()`
- Remove `ac-own-pill`, `ac-own-more` CSS

**File browser:**
- Remove ownership dot rendering from file items
- All files rendered in same style (`var(--text-secondary)`)
- Remove `fp-dot` CSS and related code

**`shortRole()` function:**
Replace the phase-based parser with the new role map:

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
```

### 9. Tests — Update for Removed Endpoints

- Remove `test_list_files_with_ownership` (ownership dots gone)
- Remove `test_list_files_dirs_have_owned` (has_owned gone)
- Remove `test_get_agent_owns` (endpoint removed)
- Update `test_list_files_root` (no `owner`/`color` fields expected)
- Update `test_files_ownership` integration test (remove or adapt)
- Remove conftest patches for `agent_owns_resolved`, `dir_has_owned`

---

## What Does NOT Change

- **warroom.sh** — all commands work as-is with role-based agents
- **Message dispatch** — tmux delivery, dedup, readiness detection — all role-agnostic
- **Status board** — universal card layout stays, agents self-report via `warroom.sh status`
- **De-boarding/re-boarding** — works the same
- **Recovery** — endpoint works the same (uses agent_config)
- **Server management header** — uptime, LaunchAgent, restart, logs — unchanged
- **Drag and drop** — file browser still works, just without ownership colors
- **Roll call** — works the same
- **Message grouping, fonts, dynamic border colors** — all stay
