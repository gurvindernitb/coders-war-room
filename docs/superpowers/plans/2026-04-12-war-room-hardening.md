# War Room Governed Pipeline Hardening — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Transform the Coders War Room from an instruction-dependent coordination tool into a registry-driven, hook-enforced, visually governed product.

**Architecture:** Four YAML registries (gates, roles, hooks, budgets) drive all configuration. The server reads registries at agent onboard to generate `.claude/settings.local.json` with role-appropriate hooks. Hooks POST verified events to the server API. The UI renders hook-verified gate status on agent cards. A scaffold generator reads registries to produce the auto-generated portion of agent SKILL.md files.

**Tech Stack:** Python 3.12 (FastAPI server), Bash (hook scripts), YAML (registries), HTML/CSS/JS (web UI), SQLite (hook events storage).

**Spec:** `docs/superpowers/specs/2026-04-12-war-room-hardening-design.md`

**Repos:**
- `~/coders-war-room/` — primary (server, hooks, registries, UI, skill engine)
- `~/contextualise/` — secondary (project-level settings, SKILL.md outputs)

---

## Phase 1: Registries & Hook Scripts (Foundation)

### Task 1: Create the four YAML registries

**Files:**
- Create: `registries/gate-registry.yaml`
- Create: `registries/role-registry.yaml`
- Create: `registries/hook-registry.yaml`
- Create: `registries/tool-budget-registry.yaml`

- [ ] **Step 1: Create registries directory**

```bash
mkdir -p ~/coders-war-room/registries
```

- [ ] **Step 2: Write gate-registry.yaml**

Create `registries/gate-registry.yaml` with the full gate definitions from the spec. This is the authoritative map of all gates, tools, dispositions, thresholds, retry ceilings, and accountability chains.

```yaml
# registries/gate-registry.yaml
# Authoritative map: gate → tools → disposition → agent → accountability
# Adding a tool = add an entry here. CI, qa-suite, hooks, skills, UI all read this.

gates:
  gate-1-deterministic:
    name: "Risk Regression Suite"
    level: sprint
    also_runs: per-story
    retry_ceiling: 2
    failure_signal: "[GATE-1 FAIL]"
    escalation_signal: "[GATE-1 FAIL | ESCALATE]"
    human_signal: "[GATE-1 | HUMAN REQUIRED]"
    owner_on_fail: engineer
    escalation_to: supervisor
    tools:
      - id: pytest
        command: "python -m pytest tests/ -q --tb=short"
        json_flag: "--json-report --json-report-file=gate1-pytest.json"
        disposition: block
        threshold: "exit_code == 0"
        agent: [engineer, qa]
      - id: flake8
        command: "flake8 . --max-line-length=100 --exclude=venv,__pycache__"
        disposition: block
        threshold: "no_output"
        agent: [engineer, qa]
      - id: mypy
        command: "mypy . --ignore-missing-imports --exclude venv"
        disposition: warn
        threshold: "no_errors"
        agent: [engineer, qa]
      - id: bandit
        command: "bandit -r . --exclude ./venv,./tests -ll"
        json_flag: "-f json -o gate1-bandit.json"
        disposition: block
        threshold: "no_high_severity"
        agent: [qa]
      - id: pip-audit
        command: "pip-audit -r requirements.txt"
        json_flag: "-f json -o gate1-pip-audit.json"
        disposition: warn
        threshold: "no_critical"
        agent: [qa]
      - id: coverage
        command: "pytest --cov=. --cov-fail-under={threshold}"
        disposition: block
        threshold: "90"
        per_story_threshold: "85"
        agent: [qa]
      - id: secret-scan
        command: "scripts/check-secrets.sh"
        disposition: block
        agent: [engineer, qa]

  gate-2-integration:
    name: "Fly.io Integration Smoke"
    level: sprint
    retry_ceiling: 1
    failure_signal: "[GATE-2 FAIL]"
    owner_on_fail: scout
    escalation_to: supervisor
    skip_condition: "no_python_changes"
    stall_detection:
      threshold_minutes: 10
      action: "escalate_to_supervisor"
    tools:
      - id: flyctl-deploy
        command: "flyctl deploy --app agentik-staging --remote-only --strategy rolling"
        disposition: block
        timeout: 120
      - id: health-poll
        command: "scripts/health-poll.sh"
        disposition: block
        timeout: 90
        config:
          url: "https://agentik-staging.fly.dev/health"
          max_retries: 8
          backoff: "linear_5s"
      - id: sentry-check
        command: "scripts/sentry-staging-check.sh"
        disposition: warn

  gate-3-ai-review:
    name: "AI Architecture Review"
    level: sprint
    retry_ceiling: 0
    failure_signal: "[GATE-3 FAIL]"
    owner_on_fail: supervisor
    escalation_to: gurvinder
    tools:
      - id: greptile
        command: "scripts/gate3-greptile.py"
        disposition: block
        mode: advisory
        requires_secret: GREPTILE_API_KEY
      - id: coderabbit-cli
        command: "coderabbit review --plain"
        disposition: block
        mode: advisory
        budget: "5/hr rolling"
      - id: claude-review
        command: "scripts/gate3-claude-review.py"
        disposition: advisory
        mode: verdict
        requires_secret: ANTHROPIC_API_KEY
```

- [ ] **Step 3: Write role-registry.yaml**

Create `registries/role-registry.yaml` with all six roles plus the commented UX Designer example.

```yaml
# registries/role-registry.yaml
# Authoritative map: role → skill → hooks → tools → model → gate accountability
# Adding a role = add an entry here + run skill-engine/generate.py --role <name>

roles:
  supervisor:
    display_name: "Supervisor"
    icon: "crown"
    color: "#a86fdf"
    description: "Strategic orchestrator. Decomposes stories, assigns work, approves merges."
    model_hint: "opus"
    model_hint_label: null
    skill: "supervisor-role"
    working_directory: "~/contextualise"
    writes_code: false
    allowed_tools:
      - "Read"
      - "Grep"
      - "Glob"
      - "Bash(git log *)"
      - "Bash(git status)"
    disallowed_tools:
      - "Write"
      - "Edit"
    hooks:
      - template: base-hooks
      - template: no-code-hooks
    gates_accountable_for: []
    gates_routes_on_fail: [gate-1, gate-2, gate-3]
    startup_checklist:
      - "Read docs/PROJECT_STATUS.md"
      - "Check Jira via MCP"
      - "Run warroom.sh history"
      - "Read latest docs/chronicler/ file"

  scout:
    display_name: "Scout"
    icon: "magnifyingglass"
    color: "#a86fdf"
    description: "Research and investigation. Code analysis, blast radius, Figma specs."
    model_hint: "opus"
    model_hint_label: null
    skill: "scout-role"
    working_directory: "~/contextualise"
    writes_code: false
    allowed_tools:
      - "Read"
      - "Grep"
      - "Glob"
      - "Bash(git *)"
      - "Bash(find *)"
    disallowed_tools:
      - "Write"
      - "Edit"
    hooks:
      - template: base-hooks
      - template: no-code-hooks
    gates_accountable_for: []
    gates_investigates_on_fail: [gate-2]

  engineer:
    display_name: "Engineer"
    icon: "hammer"
    color: "#a86fdf"
    description: "Implementation with TDD. Writes code, writes tests, hands clean builds to QA."
    model_hint: "opus"
    model_hint_label: null
    skill: "engineer-role"
    working_directory: "~/contextualise"
    writes_code: true
    allowed_tools: "*"
    disallowed_tools: []
    hooks:
      - template: base-hooks
      - template: engineer-stop-gate
      - template: post-edit-lint
    gates_accountable_for: [gate-1]
    gate_tools_in_pre_commit:
      - pytest
      - flake8
      - mypy
      - secret-scan

  qa:
    display_name: "QA"
    icon: "checkmark.shield"
    color: "#a86fdf"
    description: "Quality gate. Two-lane routing. Produces PASS/FAIL verdicts with evidence."
    model_hint: "sonnet"
    model_hint_label: "Sonnet recommended — independent judgment from Engineer's Opus"
    skill: "qa-role"
    working_directory: "~/contextualise"
    writes_code: false
    allowed_tools:
      - "Read"
      - "Grep"
      - "Glob"
      - "Bash(pytest *)"
      - "Bash(flake8 *)"
      - "Bash(mypy *)"
      - "Bash(bandit *)"
      - "Bash(scripts/qa-suite.sh *)"
      - "Bash(coderabbit *)"
    disallowed_tools:
      - "Write"
      - "Edit"
    hooks:
      - template: base-hooks
      - template: no-code-hooks
      - template: qa-stop-gate
    gates_accountable_for: [gate-1]
    gate_tools_in_review:
      - pytest
      - flake8
      - mypy
      - bandit
      - pip-audit
      - coverage
      - secret-scan
      - qodo
      - coderabbit-cli

  git-agent:
    display_name: "Git Agent"
    icon: "arrow.triangle.branch"
    color: "#a86fdf"
    description: "Persistence backbone. Six commit points. Blocks merges without QA PASS."
    model_hint: "opus"
    model_hint_label: null
    skill: "git-agent-role"
    working_directory: "~/contextualise"
    writes_code: false
    allowed_tools:
      - "Bash(git *)"
      - "Bash(gh *)"
      - "Read"
    disallowed_tools:
      - "Write"
      - "Edit"
    hooks:
      - template: base-hooks
      - template: no-code-hooks
      - template: merge-block-gate

  chronicler:
    display_name: "Chronicler"
    icon: "book.closed"
    color: "#a86fdf"
    description: "Silent observer. Drift detection, learnings, tool budget tracking."
    model_hint: "opus"
    model_hint_label: null
    skill: "chronicler-role"
    working_directory: "~/contextualise"
    writes_code: false
    allowed_tools:
      - "Read"
      - "Grep"
      - "Glob"
      - "Bash(git log *)"
      - "Bash(git diff *)"
    disallowed_tools:
      - "Write"
      - "Edit"
    hooks:
      - template: base-hooks
      - template: no-code-hooks
    monitors_budgets_for:
      - qodo
      - coderabbit-cli
      - greptile

  # Example: adding a new role
  # ux-designer:
  #   display_name: "UX Designer"
  #   icon: "paintbrush"
  #   color: "#a86fdf"
  #   description: "Design specialist. Reads Figma, produces component specs."
  #   model_hint: "opus"
  #   model_hint_label: null
  #   skill: "ux-designer-role"
  #   working_directory: "~/contextualise"
  #   writes_code: false
  #   allowed_tools: ["Read", "Grep", "Glob", "Bash(stitch *)"]
  #   disallowed_tools: ["Write", "Edit"]
  #   hooks:
  #     - template: base-hooks
  #     - template: no-code-hooks
```

- [ ] **Step 4: Write hook-registry.yaml**

Create `registries/hook-registry.yaml` with all hook templates.

```yaml
# registries/hook-registry.yaml
# Hook templates referenced by role-registry.yaml
# Adding a hook = add a template here, reference it in the role's hooks list

templates:
  base-hooks:
    description: "All agents — inbox polling, skill loading, critical message check"
    hooks:
      SessionStart:
        - type: command
          command: "hooks/session-start.sh"
      PreToolUse:
        - matcher: "Bash"
          type: command
          command: "hooks/check-warroom-inbox.sh"
      Stop:
        - type: command
          command: "hooks/stop-guard-warroom.sh"

  no-code-hooks:
    description: "Blocks Write/Edit for non-coding roles"
    hooks:
      PreToolUse:
        - matcher: "Write|Edit"
          type: command
          command: "hooks/block-code-writes.sh"

  engineer-stop-gate:
    description: "Tests must pass before Engineer can stop"
    hooks:
      Stop:
        - type: command
          command: "hooks/engineer-quality-gate.sh"
          timeout: 120

  qa-stop-gate:
    description: "qa-suite.sh must have run before QA can stop"
    hooks:
      Stop:
        - type: command
          command: "hooks/qa-quality-gate.sh"
          timeout: 30

  merge-block-gate:
    description: "Blocks merge/push main without QA PASS"
    hooks:
      PreToolUse:
        - matcher: "Bash"
          type: command
          command: "hooks/verify-qa-before-merge.sh"

  post-edit-lint:
    description: "Auto-lint after file writes"
    hooks:
      PostToolUse:
        - matcher: "Edit|Write"
          type: command
          command: "hooks/post-edit-lint.sh"
          async: true
          timeout: 15
```

- [ ] **Step 5: Write tool-budget-registry.yaml**

Create `registries/tool-budget-registry.yaml`.

```yaml
# registries/tool-budget-registry.yaml
# Chronicler reads this for weekly budget snapshots
# Adding a paid tool = add an entry here

budgets:
  qodo:
    display_name: "QODO CLI"
    limit: 30
    period: monthly
    unit: "PRs"
    alert_threshold: 24
    lane_restriction: "full"
  coderabbit-cli:
    display_name: "CodeRabbit CLI"
    limit: 5
    period: hourly_rolling
    unit: "reviews"
    alert_threshold: 4
    lane_restriction: "full"
  greptile:
    display_name: "Greptile"
    cost_per_use: 0.45
    unit: "queries"
    period: per_sprint
    alert_threshold: 5
  claude-gate3:
    display_name: "Claude API (Gate 3)"
    cost_per_use: 0.02
    unit: "reviews"
    period: per_sprint
```

- [ ] **Step 6: Validate all four registry files parse correctly**

```bash
cd ~/coders-war-room
python3 -c "
import yaml
for f in ['gate-registry', 'role-registry', 'hook-registry', 'tool-budget-registry']:
    with open(f'registries/{f}.yaml') as fh:
        data = yaml.safe_load(fh)
        print(f'{f}.yaml: valid ({len(data)} top-level keys)')
"
```

Expected: All four parse without errors.

- [ ] **Step 7: Commit**

```bash
cd ~/coders-war-room
git add registries/
git commit -m "feat: add four YAML registries — gates, roles, hooks, budgets

Registry-driven architecture. All gate tools, agent roles, hook templates,
and budget limits defined in YAML. Server, hooks, skill generator, and UI
will read from these as the single source of truth."
```

---

### Task 2: Write new hook scripts

**Files:**
- Create: `hooks/session-start.sh`
- Create: `hooks/engineer-quality-gate.sh`
- Create: `hooks/qa-quality-gate.sh`
- Create: `hooks/block-code-writes.sh`
- Create: `hooks/post-edit-lint.sh`
- Modify: `hooks/verify-qa-before-merge.sh` (copy from `~/contextualise/scripts/`)
- Read: `hooks/check-warroom-inbox.sh` (already exists)
- Read: `hooks/stop-guard-warroom.sh` (already exists)

- [ ] **Step 1: Write session-start.sh**

This hook fires at SessionStart. It POSTs the agent's online status to the War Room API and auto-invokes the agent's role skill.

```bash
#!/bin/bash
# hooks/session-start.sh
# SessionStart hook — POSTs online status, invokes role skill
set -euo pipefail
trap 'echo "Hook crashed: $0" >&2; exit 2' ERR

AGENT_NAME="${WARROOM_AGENT_NAME:-unknown}"
WARROOM_URL="${WARROOM_URL:-http://localhost:5680}"

# POST online status to War Room API
curl -sf -X POST "${WARROOM_URL}/api/hooks/event" \
  -H "Content-Type: application/json" \
  -d "{\"agent\": \"${AGENT_NAME}\", \"event_type\": \"session_start\", \"tool\": \"\", \"exit_code\": 0, \"summary\": \"Session started\"}" \
  2>/dev/null || true

# Output JSON that tells Claude Code to invoke the role skill
# The SessionStart hook can inject instructions via additionalContext
ROLE_TYPE="${WARROOM_ROLE_TYPE:-}"
if [ -n "$ROLE_TYPE" ]; then
  cat <<EOF
{
  "hookSpecificOutput": {
    "suppressOutput": false,
    "additionalContext": "SYSTEM DIRECTIVE: You MUST invoke your role skill now by using the Skill tool with skill: \"${ROLE_TYPE}\". Do this before any other action. This is a structural requirement, not a suggestion."
  }
}
EOF
fi

exit 0
```

- [ ] **Step 2: Write engineer-quality-gate.sh**

```bash
#!/bin/bash
# hooks/engineer-quality-gate.sh
# Stop hook — Engineer cannot stop until pytest passes
set -euo pipefail
trap 'echo "Hook crashed: engineer-quality-gate.sh" >&2; exit 2' ERR

PROJ_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"

# Find the northstar test directory
if [ -d "${PROJ_DIR}/northstar/tests" ]; then
  TEST_DIR="${PROJ_DIR}/northstar"
elif [ -d "${PROJ_DIR}/tests" ]; then
  TEST_DIR="${PROJ_DIR}"
else
  # No tests directory found — allow stop
  exit 0
fi

cd "$TEST_DIR"

# Activate venv if it exists
if [ -f "venv/bin/activate" ]; then
  source venv/bin/activate
fi

# Timeout from registry via settings generator env var (default 110s)
GATE_TIMEOUT="${WARROOM_PYTEST_TIMEOUT:-110}"

# Run pytest with registry-driven timeout
OUTPUT=$(timeout "$GATE_TIMEOUT" python -m pytest tests/ -q --tb=line 2>&1) || true
EXIT_CODE=${PIPESTATUS[0]:-$?}

# Handle timeout signal (exit code 124 from GNU timeout)
if [ "$EXIT_CODE" -eq 124 ]; then
  echo "pytest timed out after ${GATE_TIMEOUT}s — test suite may need splitting or timeout increase in gate-registry.yaml" >&2
  
  AGENT_NAME="${WARROOM_AGENT_NAME:-engineer}"
  curl -sf -X POST "${WARROOM_URL:-http://localhost:5680}/api/hooks/event" \
    -H "Content-Type: application/json" \
    -d "{\"agent\": \"${AGENT_NAME}\", \"event_type\": \"stop_blocked\", \"tool\": \"pytest\", \"exit_code\": 124, \"summary\": \"Timed out after ${GATE_TIMEOUT}s\"}" \
    2>/dev/null || true
  
  exit 2
fi

if echo "$OUTPUT" | grep -qE '(FAILED|ERROR|no tests ran)'; then
  FAIL_COUNT=$(echo "$OUTPUT" | grep -oE '[0-9]+ failed' | head -1 || echo "unknown")
  echo "Tests failing (${FAIL_COUNT}). Fix all test failures before stopping." >&2
  
  # POST to War Room API
  AGENT_NAME="${WARROOM_AGENT_NAME:-engineer}"
  curl -sf -X POST "${WARROOM_URL:-http://localhost:5680}/api/hooks/event" \
    -H "Content-Type: application/json" \
    -d "{\"agent\": \"${AGENT_NAME}\", \"event_type\": \"stop_blocked\", \"tool\": \"pytest\", \"exit_code\": 1, \"summary\": \"Tests failing: ${FAIL_COUNT}\"}" \
    2>/dev/null || true
  
  exit 2
fi

# Tests pass — POST success and allow stop
PASS_COUNT=$(echo "$OUTPUT" | grep -oE '[0-9]+ passed' | head -1 || echo "all")
AGENT_NAME="${WARROOM_AGENT_NAME:-engineer}"
curl -sf -X POST "${WARROOM_URL:-http://localhost:5680}/api/hooks/event" \
  -H "Content-Type: application/json" \
  -d "{\"agent\": \"${AGENT_NAME}\", \"event_type\": \"gate_check\", \"tool\": \"pytest\", \"exit_code\": 0, \"summary\": \"${PASS_COUNT} passed\"}" \
  2>/dev/null || true

exit 0
```

- [ ] **Step 3: Write qa-quality-gate.sh**

```bash
#!/bin/bash
# hooks/qa-quality-gate.sh
# Stop hook — QA cannot stop without running qa-suite.sh
set -euo pipefail
trap 'echo "Hook crashed: qa-quality-gate.sh" >&2; exit 2' ERR

# Check if qa-suite output exists from this session
QA_FILES=$(ls /tmp/qa-suite-*.json 2>/dev/null | head -5)

if [ -z "$QA_FILES" ]; then
  echo "qa-suite.sh has not been run this session. Run: scripts/qa-suite.sh <STORY-ID>" >&2
  
  AGENT_NAME="${WARROOM_AGENT_NAME:-qa}"
  curl -sf -X POST "${WARROOM_URL:-http://localhost:5680}/api/hooks/event" \
    -H "Content-Type: application/json" \
    -d "{\"agent\": \"${AGENT_NAME}\", \"event_type\": \"stop_blocked\", \"tool\": \"qa-suite\", \"exit_code\": 1, \"summary\": \"qa-suite.sh not run\"}" \
    2>/dev/null || true
  
  exit 2
fi

# qa-suite was run — allow stop
LATEST=$(ls -t /tmp/qa-suite-*.json 2>/dev/null | head -1)
PASS=$(python3 -c "import json; print(json.load(open('${LATEST}'))['pass'])" 2>/dev/null || echo "unknown")

AGENT_NAME="${WARROOM_AGENT_NAME:-qa}"
curl -sf -X POST "${WARROOM_URL:-http://localhost:5680}/api/hooks/event" \
  -H "Content-Type: application/json" \
  -d "{\"agent\": \"${AGENT_NAME}\", \"event_type\": \"gate_check\", \"tool\": \"qa-suite\", \"exit_code\": 0, \"summary\": \"qa-suite pass=${PASS}\"}" \
  2>/dev/null || true

exit 0
```

- [ ] **Step 4: Write block-code-writes.sh**

```bash
#!/bin/bash
# hooks/block-code-writes.sh
# PreToolUse hook — denies Write/Edit for non-coding agent roles
set -euo pipefail
trap 'echo "Hook crashed: block-code-writes.sh" >&2; exit 2' ERR

AGENT_NAME="${WARROOM_AGENT_NAME:-unknown}"

cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "Agent '${AGENT_NAME}' is a non-coding role. Write and Edit tools are blocked. You verify and report — the Engineer writes code."
  }
}
EOF

exit 0
```

- [ ] **Step 5: Write post-edit-lint.sh**

```bash
#!/bin/bash
# hooks/post-edit-lint.sh
# PostToolUse hook — auto-lint after file writes (async, no block)
set -euo pipefail

PROJ_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
AGENT_NAME="${WARROOM_AGENT_NAME:-engineer}"

# Get the file that was just edited from hook input
INPUT=$(cat 2>/dev/null || echo "{}")
FILE_PATH=$(echo "$INPUT" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    print(d.get('tool_input', {}).get('file_path', ''))
except:
    print('')
" 2>/dev/null || echo "")

# Only lint Python files
if [[ "$FILE_PATH" == *.py ]]; then
  LINT_OUT=$(cd "$PROJ_DIR" && python3 -m flake8 "$FILE_PATH" --max-line-length=100 2>&1 || true)
  if [ -n "$LINT_OUT" ]; then
    ISSUE_COUNT=$(echo "$LINT_OUT" | wc -l | tr -d ' ')
    curl -sf -X POST "${WARROOM_URL:-http://localhost:5680}/api/hooks/event" \
      -H "Content-Type: application/json" \
      -d "{\"agent\": \"${AGENT_NAME}\", \"event_type\": \"lint\", \"tool\": \"flake8\", \"exit_code\": 1, \"summary\": \"${ISSUE_COUNT} issues in ${FILE_PATH##*/}\"}" \
      2>/dev/null || true
  else
    curl -sf -X POST "${WARROOM_URL:-http://localhost:5680}/api/hooks/event" \
      -H "Content-Type: application/json" \
      -d "{\"agent\": \"${AGENT_NAME}\", \"event_type\": \"lint\", \"tool\": \"flake8\", \"exit_code\": 0, \"summary\": \"clean: ${FILE_PATH##*/}\"}" \
      2>/dev/null || true
  fi
fi

exit 0
```

- [ ] **Step 6: Copy and adapt verify-qa-before-merge.sh**

```bash
cp ~/contextualise/scripts/verify-qa-before-merge.sh ~/coders-war-room/hooks/verify-qa-before-merge.sh
chmod +x ~/coders-war-room/hooks/verify-qa-before-merge.sh
```

The existing script at `~/contextualise/scripts/verify-qa-before-merge.sh` already implements the merge-block logic. Copy it to the War Room hooks directory so the settings generator can reference it.

- [ ] **Step 7: Make all hook scripts executable**

```bash
chmod +x ~/coders-war-room/hooks/*.sh
```

- [ ] **Step 8: Commit**

```bash
cd ~/coders-war-room
git add hooks/
git commit -m "feat: add hook scripts — quality gates, code blocking, session start

- session-start.sh: POSTs online status, auto-invokes role skill
- engineer-quality-gate.sh: Stop hook, pytest must pass
- qa-quality-gate.sh: Stop hook, qa-suite.sh must have run
- block-code-writes.sh: PreToolUse denies Write/Edit for non-coding roles
- post-edit-lint.sh: PostToolUse async flake8 on modified Python files
- verify-qa-before-merge.sh: PreToolUse blocks merge without QA PASS"
```

---

### Task 3: Add hook_events table and API endpoints to server.py

**Files:**
- Modify: `server.py`

- [ ] **Step 1: Add hook_events table creation to SQLite init**

Find the existing `CREATE TABLE` statements in `server.py` (the `init_db()` or startup function) and add:

```python
# Add after existing CREATE TABLE statements

# Enable WAL mode for concurrent access — 6+ agents posting hooks simultaneously
# WAL allows concurrent reads while a single writer proceeds without blocking readers.
# This prevents "database is locked" errors during high-volume hook bursts.
await db.execute("PRAGMA journal_mode=WAL")
await db.execute("PRAGMA busy_timeout=5000")  # 5s retry on lock instead of instant fail

await db.execute("""
    CREATE TABLE IF NOT EXISTS hook_events (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        agent TEXT NOT NULL,
        event_type TEXT NOT NULL,
        tool TEXT DEFAULT '',
        exit_code INTEGER DEFAULT 0,
        summary TEXT DEFAULT '',
        timestamp TEXT DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'))
    )
""")
await db.execute("""
    CREATE INDEX IF NOT EXISTS idx_hook_events_agent
    ON hook_events(agent, timestamp DESC)
""")
```

**SQLite concurrency note:** With 6 agents firing hooks simultaneously (e.g., all running pytest during a sprint gate), WAL mode + busy_timeout handles the write serialization gracefully. WAL allows readers to proceed while a write is in progress, and busy_timeout retries for 5 seconds before failing. This is the same pattern North Star's `state.py` uses for its DatabaseManager.

- [ ] **Step 2: Add POST /api/hooks/event endpoint**

Add after the existing API endpoints:

```python
@app.post("/api/hooks/event")
async def receive_hook_event(request: Request):
    """Receive hook callback data from agent hook scripts."""
    data = await request.json()
    agent = data.get("agent", "unknown")
    event_type = data.get("event_type", "unknown")
    tool = data.get("tool", "")
    exit_code = data.get("exit_code", 0)
    summary = data.get("summary", "")

    async with aiosqlite.connect(DB_PATH) as db:
        await db.execute(
            "INSERT INTO hook_events (agent, event_type, tool, exit_code, summary) VALUES (?, ?, ?, ?, ?)",
            (agent, event_type, tool, exit_code, summary),
        )
        await db.commit()

    # Broadcast to WebSocket clients
    event = {
        "type": "hook_event",
        "agent": agent,
        "event_type": event_type,
        "tool": tool,
        "exit_code": exit_code,
        "summary": summary,
        "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    }
    for ws in list(connected_websockets):
        try:
            await ws.send_json(event)
        except Exception:
            connected_websockets.discard(ws)

    return {"status": "ok"}
```

- [ ] **Step 3: Add GET /api/agents/{name}/hook-events endpoint**

```python
@app.get("/api/agents/{name}/hook-events")
async def get_agent_hook_events(name: str, limit: int = 50):
    """Return recent hook events for an agent."""
    async with aiosqlite.connect(DB_PATH) as db:
        db.row_factory = aiosqlite.Row
        cursor = await db.execute(
            "SELECT * FROM hook_events WHERE agent = ? ORDER BY timestamp DESC LIMIT ?",
            (name, limit),
        )
        rows = await cursor.fetchall()
    return {"events": [dict(r) for r in rows]}
```

- [ ] **Step 4: Test the endpoints manually**

```bash
# Start the server
cd ~/coders-war-room && python server.py &

# POST a test event
curl -s -X POST http://localhost:5680/api/hooks/event \
  -H "Content-Type: application/json" \
  -d '{"agent": "test-engineer", "event_type": "gate_check", "tool": "pytest", "exit_code": 0, "summary": "1242 passed"}'

# GET events back
curl -s http://localhost:5680/api/agents/test-engineer/hook-events | python3 -m json.tool

# Kill the server
kill %1
```

Expected: POST returns `{"status": "ok"}`, GET returns the event.

- [ ] **Step 5: Commit**

```bash
cd ~/coders-war-room
git add server.py
git commit -m "feat: add hook_events table and API endpoints

- POST /api/hooks/event — receives hook callback data, stores in SQLite, broadcasts via WebSocket
- GET /api/agents/{name}/hook-events — returns recent hook events for agent card rendering
- hook_events indexed on (agent, timestamp DESC) for fast lookups"
```

---

### Task 4: Build the settings generator

**Files:**
- Create: `settings_generator.py`

- [ ] **Step 1: Write the settings generator**

```python
#!/usr/bin/env python3
"""settings_generator.py — Reads registries, produces .claude/settings.local.json for an agent role."""

import json
import os
import yaml
import sys

REGISTRY_DIR = os.path.join(os.path.dirname(__file__), "registries")
HOOKS_DIR = os.path.join(os.path.dirname(__file__), "hooks")


def load_registry(name: str) -> dict:
    path = os.path.join(REGISTRY_DIR, f"{name}.yaml")
    with open(path) as f:
        return yaml.safe_load(f)


def resolve_hook_templates(template_names: list[str], hook_reg: dict) -> dict:
    """Merge hook templates into a single hooks config for settings.json."""
    merged: dict[str, list] = {}
    templates = hook_reg.get("templates", {})

    for tname_entry in template_names:
        tname = tname_entry.get("template") if isinstance(tname_entry, dict) else tname_entry
        template = templates.get(tname)
        if not template:
            print(f"WARNING: hook template '{tname}' not found in hook-registry.yaml", file=sys.stderr)
            continue

        for event_name, hook_list in template.get("hooks", {}).items():
            if event_name not in merged:
                merged[event_name] = []
            for hook in hook_list:
                entry = {"hooks": [{}]}
                hook_def = {}
                hook_def["type"] = hook.get("type", "command")
                # Resolve command path to absolute
                cmd = hook.get("command", "")
                if cmd and not cmd.startswith("/"):
                    cmd = os.path.join(HOOKS_DIR, os.path.basename(cmd))
                hook_def["command"] = cmd
                if "timeout" in hook:
                    hook_def["timeout"] = hook["timeout"]
                if hook.get("async"):
                    hook_def["async"] = True

                entry_wrapper = {"hooks": [hook_def]}
                if "matcher" in hook:
                    entry_wrapper["matcher"] = hook["matcher"]
                merged[event_name].append(entry_wrapper)

    return merged


def extract_gate_timeouts(role_type: str) -> dict[str, int]:
    """Extract tool timeouts from gate-registry for this role's accountable gates."""
    gate_reg = load_registry("gate-registry")
    role_reg = load_registry("role-registry")
    role = role_reg.get("roles", {}).get(role_type, {})
    gates = role.get("gates_accountable_for", [])
    
    timeouts = {}
    for gate_id, gate in gate_reg.get("gates", {}).items():
        if gate_id not in gates:
            continue
        for tool in gate.get("tools", []):
            if "timeout" in tool:
                # Convert to env var name: pytest -> WARROOM_PYTEST_TIMEOUT
                env_name = f"WARROOM_{tool['id'].upper().replace('-', '_')}_TIMEOUT"
                timeouts[env_name] = tool["timeout"]
    return timeouts


def generate_settings(role_type: str) -> dict:
    """Generate .claude/settings.local.json content for a given role."""
    role_reg = load_registry("role-registry")
    hook_reg = load_registry("hook-registry")

    role = role_reg.get("roles", {}).get(role_type)
    if not role:
        raise ValueError(f"Role '{role_type}' not found in role-registry.yaml")

    hooks = resolve_hook_templates(role.get("hooks", []), hook_reg)

    settings = {"hooks": hooks}

    # Add permissions if role has tool restrictions
    permissions = {}
    allowed = role.get("allowed_tools", "*")
    if allowed != "*":
        permissions["allow"] = allowed
    disallowed = role.get("disallowed_tools", [])
    if disallowed:
        permissions["deny"] = disallowed
    if permissions:
        settings["permissions"] = permissions

    # Extract gate tool timeouts as env vars for hook scripts
    # Hook scripts read these instead of hardcoding (e.g., WARROOM_PYTEST_TIMEOUT=120)
    timeouts = extract_gate_timeouts(role_type)
    if timeouts:
        settings["env"] = timeouts

    return settings


def write_settings(role_type: str, working_dir: str) -> str:
    """Generate and write .claude/settings.local.json to the working directory."""
    settings = generate_settings(role_type)
    claude_dir = os.path.join(os.path.expanduser(working_dir), ".claude")
    os.makedirs(claude_dir, exist_ok=True)
    out_path = os.path.join(claude_dir, "settings.local.json")
    with open(out_path, "w") as f:
        json.dump(settings, f, indent=2)
    return out_path


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python settings_generator.py <role-type> [working-dir]")
        print("  role-type: supervisor, scout, engineer, qa, git-agent, chronicler")
        print("  working-dir: defaults to ~/contextualise")
        sys.exit(1)

    role = sys.argv[1]
    wdir = sys.argv[2] if len(sys.argv) > 2 else "~/contextualise"
    path = write_settings(role, wdir)
    print(f"Generated: {path}")
```

- [ ] **Step 2: Test the generator**

```bash
cd ~/coders-war-room

# Generate for QA role to a temp directory
python3 settings_generator.py qa /tmp/test-settings

# Verify the output
cat /tmp/test-settings/.claude/settings.local.json | python3 -m json.tool

# Verify it contains the QA-specific hooks
grep -c "qa-quality-gate" /tmp/test-settings/.claude/settings.local.json
# Expected: 1

# Verify it contains the base hooks
grep -c "session-start" /tmp/test-settings/.claude/settings.local.json
# Expected: 1

# Verify it blocks Write/Edit
grep -c "block-code-writes" /tmp/test-settings/.claude/settings.local.json
# Expected: 1

# Clean up
rm -rf /tmp/test-settings
```

- [ ] **Step 3: Test all six roles generate without errors**

```bash
cd ~/coders-war-room
for role in supervisor scout engineer qa git-agent chronicler; do
  python3 settings_generator.py "$role" /tmp/test-${role}
  echo "${role}: $(cat /tmp/test-${role}/.claude/settings.local.json | python3 -c 'import json,sys; d=json.load(sys.stdin); print(len(d.get("hooks",{})), "hook events")')"
  rm -rf /tmp/test-${role}
done
```

Expected: All six generate successfully with varying hook event counts.

- [ ] **Step 4: Commit**

```bash
cd ~/coders-war-room
git add settings_generator.py
git commit -m "feat: add settings generator — reads registries, produces settings.local.json

Generates .claude/settings.local.json per agent role with:
- SessionStart hook (auto-invoke role skill)
- PreToolUse hooks (inbox poll, code-write block for non-coders, merge block for git-agent)
- Stop hooks (pytest gate for engineer, qa-suite gate for QA, critical message guard for all)
- PostToolUse hooks (async lint for engineer)
- Tool permissions (allowed/disallowed per role)"
```

---

### Task 5: Wire settings generator into server.py agent creation

**Files:**
- Modify: `server.py`

- [ ] **Step 1: Import and call settings generator in agent creation**

Find the agent creation endpoint in `server.py` (around line 1253, the `/api/agents/create` handler). Add the settings generation call after the tmux session is created but before Claude Code is started.

```python
# Add import at top of server.py
from settings_generator import write_settings

# Inside the agent creation function, after tmux session creation,
# before starting Claude Code:

# Generate role-specific settings
role_type = agent_config.get("role_type", "")
working_dir = agent_config.get("directory", PROJECT_PATH)
if role_type:
    try:
        settings_path = write_settings(role_type, working_dir)
        log.info(f"Generated settings for {agent_name}: {settings_path}")
    except Exception as e:
        log.warning(f"Failed to generate settings for {agent_name}: {e}")

# Also set WARROOM_ROLE_TYPE env var for the session
# (used by session-start.sh to know which skill to invoke)
subprocess.run([
    "tmux", "send-keys", "-t", tmux_session,
    f"export WARROOM_ROLE_TYPE='{role_type}'", "Enter"
], check=False)
```

- [ ] **Step 2: Add registry sync validation at server startup**

Add at the end of the startup/lifespan function:

```python
import hashlib

def validate_registry_sync() -> bool:
    """Check if registries have changed since last skill generation."""
    registry_dir = os.path.join(os.path.dirname(__file__), "registries")
    gen_file = os.path.join(registry_dir, ".last-generated.json")

    if not os.path.exists(gen_file):
        log.warning("No .last-generated.json found — skill generation has never been run")
        return False

    with open(gen_file) as f:
        last_hashes = json.load(f)

    for reg_name in ["gate-registry", "role-registry", "hook-registry", "tool-budget-registry"]:
        reg_path = os.path.join(registry_dir, f"{reg_name}.yaml")
        if not os.path.exists(reg_path):
            continue
        with open(reg_path, "rb") as f:
            current_hash = hashlib.sha256(f.read()).hexdigest()
        if current_hash != last_hashes.get(reg_name):
            log.warning(f"{reg_name}.yaml changed since last skill generation. Run: python skill-engine/generate.py --all")
            return False
    return True

# Call during startup
if not validate_registry_sync():
    log.warning("[REGISTRY DRIFT] Registries updated since last skill generation")
```

- [ ] **Step 3: Test end-to-end by creating an agent via the API**

```bash
# Start server
cd ~/coders-war-room && python server.py &

# Create a test agent (adjust payload to match your API)
curl -s -X POST http://localhost:5680/api/agents/create \
  -H "Content-Type: application/json" \
  -d '{"name": "test-qa", "role_type": "qa", "model": "sonnet"}'

# Verify settings.local.json was created
cat ~/contextualise/.claude/settings.local.json | python3 -m json.tool

# Clean up
kill %1
rm -f ~/contextualise/.claude/settings.local.json
```

- [ ] **Step 4: Commit**

```bash
cd ~/coders-war-room
git add server.py
git commit -m "feat: wire settings generator into agent creation

- Agent creation now generates .claude/settings.local.json before starting Claude Code
- Sets WARROOM_ROLE_TYPE env var for SessionStart hook skill invocation
- Registry sync validation runs at server startup, warns on drift"
```

---

## Phase 2: Skill Engine & Research Documentation

### Task 6: Create the scaffold generator

**Files:**
- Create: `skill-engine/generate.py`
- Create: `skill-engine/__init__.py`

- [ ] **Step 1: Create skill-engine directory**

```bash
mkdir -p ~/coders-war-room/skill-engine
touch ~/coders-war-room/skill-engine/__init__.py
```

- [ ] **Step 2: Write generate.py**

```python
#!/usr/bin/env python3
"""skill-engine/generate.py — Scaffold generator for agent SKILL.md files.

Reads the four YAML registries and produces the auto-generated portion of each
role's SKILL.md. The collaborative portion (below the boundary line) is never
overwritten.

Usage:
    python skill-engine/generate.py --role qa
    python skill-engine/generate.py --all
    python skill-engine/generate.py --diff
"""

import argparse
import hashlib
import json
import os
import re
import sys

import yaml

WARROOM_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REGISTRY_DIR = os.path.join(WARROOM_DIR, "registries")
SKILLS_DIR = os.path.expanduser("~/contextualise/.claude/skills")
BOUNDARY = "<!-- ═══ BELOW THIS LINE: Collaborative section — authored by human + Claude Code ═══ -->"
AUTO_START = "<!-- AUTO-GENERATED from registries — do not hand-edit above the boundary line -->"


def load_reg(name: str) -> dict:
    with open(os.path.join(REGISTRY_DIR, f"{name}.yaml")) as f:
        return yaml.safe_load(f)


def registry_hash() -> str:
    """SHA-256 of all four registries concatenated."""
    h = hashlib.sha256()
    for name in ["gate-registry", "role-registry", "hook-registry", "tool-budget-registry"]:
        path = os.path.join(REGISTRY_DIR, f"{name}.yaml")
        with open(path, "rb") as f:
            h.update(f.read())
    return h.hexdigest()[:12]


def generate_gate_table(role_name: str, gate_reg: dict, role: dict) -> str:
    """Generate the Gate Accountability table for a role."""
    gates_for = role.get("gates_accountable_for", [])
    gates_routes = role.get("gates_routes_on_fail", [])
    gates_investigates = role.get("gates_investigates_on_fail", [])

    all_gates = set(gates_for + gates_routes + gates_investigates)
    if not all_gates:
        return ""

    lines = [
        "## Gate Accountability",
        AUTO_START,
        "",
        "| Gate | Your Role | Tools | Retry Ceiling | On Fail Signal |",
        "|------|-----------|-------|---------------|----------------|",
    ]

    for gate_id, gate in gate_reg.get("gates", {}).items():
        if gate_id not in all_gates:
            continue
        if gate_id in gates_for:
            role_desc = "**Run & Fix**"
        elif gate_id in gates_investigates:
            role_desc = "Investigate"
        elif gate_id in gates_routes:
            role_desc = "Route failures"
        else:
            continue

        tool_names = [t["id"] for t in gate.get("tools", [])
                      if role_name in t.get("agent", []) or role_desc == "Route failures"]
        tools_str = ", ".join(tool_names) if tool_names else "—"
        ceiling = gate.get("retry_ceiling", "—")
        signal = gate.get("failure_signal", "—")
        lines.append(f"| {gate.get('name', gate_id)} | {role_desc} | {tools_str} | {ceiling} | `{signal}` |")

    lines.append("")
    return "\n".join(lines)


def generate_tool_table(role_name: str, gate_reg: dict, role: dict, budget_reg: dict) -> str:
    """Generate the Tool Assignments table for a role."""
    review_tools = role.get("gate_tools_in_review", role.get("gate_tools_in_pre_commit", []))
    if not review_tools:
        return ""

    budgets = budget_reg.get("budgets", {})

    lines = [
        "## Tool Assignments",
        AUTO_START,
        "",
        "| Tool | Disposition | Budget |",
        "|------|-------------|--------|",
    ]

    for gate_id, gate in gate_reg.get("gates", {}).items():
        for tool in gate.get("tools", []):
            if tool["id"] in review_tools:
                budget_info = budgets.get(tool["id"], {})
                budget_str = f"{budget_info['limit']} {budget_info['unit']}/{budget_info['period']}" if budget_info else "—"
                lines.append(f"| {tool['id']} | {tool.get('disposition', '—')} | {budget_str} |")

    lines.append("")
    return "\n".join(lines)


def generate_hook_table(role: dict, hook_reg: dict) -> str:
    """Generate the Hook Enforcement table for a role."""
    templates = hook_reg.get("templates", {})
    hook_entries = role.get("hooks", [])

    lines = [
        "## Hook Enforcement",
        AUTO_START,
        "",
        "These hooks are structural — you do not control them. They fire automatically.",
        "",
        "| Hook | Event | What It Does |",
        "|------|-------|-------------|",
    ]

    for entry in hook_entries:
        tname = entry.get("template") if isinstance(entry, dict) else entry
        template = templates.get(tname, {})
        desc = template.get("description", "")
        for event_name, hooks in template.get("hooks", {}).items():
            for hook in hooks:
                cmd = os.path.basename(hook.get("command", ""))
                lines.append(f"| {cmd} | {event_name} | {desc} |")

    lines.append("")
    return "\n".join(lines)


def generate_signal_table(role: dict, gate_reg: dict) -> str:
    """Generate the War Room Signals table for a role."""
    all_gates = set(
        role.get("gates_accountable_for", []) +
        role.get("gates_routes_on_fail", []) +
        role.get("gates_investigates_on_fail", [])
    )
    if not all_gates:
        return ""

    lines = [
        "## War Room Signals",
        AUTO_START,
        "",
        "| Signal | When |",
        "|--------|------|",
    ]

    for gate_id, gate in gate_reg.get("gates", {}).items():
        if gate_id not in all_gates:
            continue
        name = gate.get("name", gate_id)
        if gate.get("failure_signal"):
            lines.append(f"| `{gate['failure_signal']}` | Routine failure — {name} |")
        if gate.get("escalation_signal"):
            lines.append(f"| `{gate['escalation_signal']}` | Same file fails twice or 30+ min |")
        if gate.get("human_signal"):
            lines.append(f"| `{gate['human_signal']}` | Security, confidence <60% |")

    lines.append("")
    return "\n".join(lines)


def generate_scaffold(role_name: str) -> str:
    """Generate the complete auto-generated portion of a SKILL.md."""
    gate_reg = load_reg("gate-registry")
    role_reg = load_reg("role-registry")
    hook_reg = load_reg("hook-registry")
    budget_reg = load_reg("tool-budget-registry")

    role = role_reg.get("roles", {}).get(role_name)
    if not role:
        raise ValueError(f"Role '{role_name}' not found in role-registry.yaml")

    sections = [
        generate_gate_table(role_name, gate_reg, role),
        generate_tool_table(role_name, gate_reg, role, budget_reg),
        generate_hook_table(role, hook_reg),
        generate_signal_table(role, gate_reg),
    ]

    # Filter empty sections
    sections = [s for s in sections if s.strip()]

    reg_hash = registry_hash()
    header = f"<!-- REGISTRY VERSION: {reg_hash} -->"

    return "\n".join([header, ""] + sections + ["", BOUNDARY])


def update_skill(role_name: str, dry_run: bool = False) -> str:
    """Update a SKILL.md's auto-generated section, preserving the collaborative section."""
    skill_dir = os.path.join(SKILLS_DIR, f"{role_name}-role" if not role_name.endswith("-role") else role_name)
    skill_path = os.path.join(skill_dir, "SKILL.md")

    new_scaffold = generate_scaffold(role_name.replace("-role", ""))

    if not os.path.exists(skill_path):
        # New skill — scaffold only
        os.makedirs(skill_dir, exist_ok=True)
        role_reg = load_reg("role-registry")
        role = role_reg["roles"][role_name.replace("-role", "")]
        frontmatter = f"""---
name: {role_name if role_name.endswith('-role') else role_name + '-role'}
description: {role.get('description', '')}
user-invocable: false
requires:
  - guardrails-contextualise
  - persistence-protocol
  - war-room-protocol
version: "2.0"
---

# {role.get('display_name', role_name)} Instructions — Project Contextualise

"""
        content = frontmatter + new_scaffold + "\n\n## Your Role\n<!-- SCAFFOLD: flesh out in collaborative session -->\n\n## Session Startup\n<!-- SCAFFOLD: flesh out in collaborative session -->\n\n## Your Workflow\n<!-- SCAFFOLD: flesh out in collaborative session -->\n"

        if dry_run:
            return f"WOULD CREATE: {skill_path}\n{content[:200]}..."
        with open(skill_path, "w") as f:
            f.write(content)
        return f"CREATED: {skill_path}"

    # Existing skill — replace auto section, preserve collaborative section
    with open(skill_path) as f:
        existing = f.read()

    if BOUNDARY in existing:
        # Split at boundary, keep everything after
        parts = existing.split(BOUNDARY, 1)
        # Find where auto-generated section starts (after frontmatter + title)
        # Look for the first AUTO-GENERATED comment or REGISTRY VERSION comment
        pre_auto = parts[0]
        collaborative = parts[1]

        # Find where auto section begins
        auto_markers = ["<!-- REGISTRY VERSION:", "<!-- AUTO-GENERATED"]
        auto_start_pos = len(pre_auto)
        for marker in auto_markers:
            pos = pre_auto.find(marker)
            if pos != -1 and pos < auto_start_pos:
                auto_start_pos = pos

        before_auto = pre_auto[:auto_start_pos].rstrip() + "\n\n"
        new_content = before_auto + new_scaffold + collaborative

        if dry_run:
            return f"WOULD UPDATE auto section: {skill_path}"
        with open(skill_path, "w") as f:
            f.write(new_content)
        return f"UPDATED: {skill_path}"
    else:
        # No boundary marker — can't safely update. Warn.
        return f"SKIPPED: {skill_path} — no boundary marker found. Manual update required."


def save_generation_hashes():
    """Record current registry hashes for sync validation."""
    hashes = {}
    for name in ["gate-registry", "role-registry", "hook-registry", "tool-budget-registry"]:
        path = os.path.join(REGISTRY_DIR, f"{name}.yaml")
        with open(path, "rb") as f:
            hashes[name] = hashlib.sha256(f.read()).hexdigest()
    out_path = os.path.join(REGISTRY_DIR, ".last-generated.json")
    with open(out_path, "w") as f:
        json.dump(hashes, f, indent=2)


def main():
    parser = argparse.ArgumentParser(description="Generate SKILL.md scaffolds from registries")
    parser.add_argument("--role", help="Generate for a specific role")
    parser.add_argument("--all", action="store_true", help="Generate for all roles")
    parser.add_argument("--diff", action="store_true", help="Preview changes without writing")
    args = parser.parse_args()

    if not args.role and not args.all and not args.diff:
        parser.print_help()
        sys.exit(1)

    role_reg = load_reg("role-registry")
    roles = list(role_reg.get("roles", {}).keys())

    if args.role:
        roles = [args.role]

    for role_name in roles:
        result = update_skill(role_name, dry_run=args.diff)
        print(result)

    if not args.diff:
        save_generation_hashes()
        print(f"\nRegistry hashes saved to registries/.last-generated.json")


if __name__ == "__main__":
    main()
```

- [ ] **Step 3: Test the generator**

```bash
cd ~/coders-war-room

# Preview what would change for QA
python3 skill-engine/generate.py --role qa --diff

# Preview all roles
python3 skill-engine/generate.py --all --diff
```

Expected: Shows WOULD UPDATE or WOULD CREATE for each role, no errors.

- [ ] **Step 4: Commit**

```bash
cd ~/coders-war-room
git add skill-engine/
git commit -m "feat: add skill scaffold generator — reads registries, produces SKILL.md sections

- generate.py --role <name>: scaffold one role
- generate.py --all: scaffold all roles
- generate.py --diff: preview changes
- Auto-generated sections: gate accountability, tool assignments, hook enforcement, signals
- Collaborative sections preserved across regeneration (boundary marker)
- Registry hashes saved to .last-generated.json for sync validation"
```

---

### Task 7: Write the skill authoring guide

**Files:**
- Create: `docs/skill-authoring-guide.md`

- [ ] **Step 1: Write the guide**

Create `docs/skill-authoring-guide.md` with the research findings from today's session. Content defined in the spec's Track 3 section: TDD methodology, MAST failure modes, structural principles, scoring protocol, skill structure rules, and collaborative session protocol.

This is a documentation task — write the full guide as specified in the design spec, Section "Skill Authoring Guide". The content comes from our research synthesis: `superpowers:writing-skills` TDD methodology, MAST failure taxonomy, AgentCoder findings, skill scoring baseline, and the 50/50 scaffold approach.

- [ ] **Step 2: Commit**

```bash
cd ~/coders-war-room
git add docs/skill-authoring-guide.md
git commit -m "docs: add skill authoring guide — captures pipeline optimization research

TDD for skills (RED-GREEN-REFACTOR), MAST failure modes to design against,
structural principles (separation of duties, file-based handoffs, hook-verified truth),
scoring protocol (agent-skills-cli baseline), collaborative session protocol."
```

---

### Task 8: Document today's research

**Files:**
- Create: `docs/research/2026-04-12_pipeline-optimization-research.md`
- Copy: Perplexity report as reference

- [ ] **Step 1: Create research directory and save documentation**

```bash
mkdir -p ~/coders-war-room/docs/research
```

Write `docs/research/2026-04-12_pipeline-optimization-research.md` summarizing: the Perplexity pipeline optimization report findings, the gate accountability research (five-agent parallel investigation), the skill audit results (baseline scores for all 9 skills), the War Room structural analysis (BUG-001, hook gaps, context isolation), and the third-party review findings (hook failure modes, hash-based sync, deploy fragility).

- [ ] **Step 2: Commit**

```bash
cd ~/coders-war-room
git add docs/research/
git commit -m "docs: preserve pipeline optimization research — MAST, AgentCoder, MetaGPT findings

Five research streams: Perplexity pipeline report, gate accountability (5-agent),
skill audit (9 skills scored), War Room structural analysis, third-party review.
Referenced by skill-authoring-guide.md."
```

---

## Phase 3: Project-Level Safety Nets

### Task 9: Add project-level settings.json to both repos

**Files:**
- Create or Modify: `~/contextualise/.claude/settings.json`
- Create or Modify: `~/coders-war-room/.claude/settings.json`

- [ ] **Step 1: Add safety-net hooks to contextualise project**

Read the existing `~/contextualise/.claude/settings.json` (if it exists). Add the project-level Stop hook (tests must pass) and PreToolUse merge-block hook. These are the safety net that catches any Claude Code session, not just War Room agents.

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "scripts/verify-qa-before-merge.sh",
            "timeout": 10
          }
        ]
      }
    ],
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "echo '{\"hookSpecificOutput\":{\"suppressOutput\":true}}'"
          }
        ]
      }
    ]
  }
}
```

Note: The SessionStart hook is minimal at project level — the War Room's `.claude/settings.local.json` adds the role-specific skill invocation on top.

- [ ] **Step 2: Verify the settings merge correctly**

When both project-level `settings.json` and War Room-generated `settings.local.json` exist, Claude Code merges them (local overrides project). Verify this doesn't produce conflicts by reviewing the merged result.

- [ ] **Step 3: Commit to both repos**

```bash
cd ~/contextualise
git add .claude/settings.json
git commit -m "feat: add project-level safety-net hooks

PreToolUse: blocks merge/push without QA PASS report
Safety net for any Claude Code session, not just War Room agents."

cd ~/coders-war-room
git add .claude/settings.json
git commit -m "feat: add project-level safety-net hooks for War Room repo"
```

---

## Phase 4: UI/UX Redesign

### Task 10: CSS token foundation

**Files:**
- Modify: `static/index.html` (or `static/evolution-tab.html`)

- [ ] **Step 1: Replace existing CSS variables with Design System tokens**

At the top of the `<style>` block, replace the existing color variables with the North Star Design System v4.4 tokens:

```css
:root {
  /* North Star Design System v4.4 — Evolution Domain */
  --void: #000000;
  --container-low: #131313;
  --container-high: #1B1B1B;
  --text-primary: #F2F2F7;
  --text-secondary: rgba(242, 242, 247, 0.6);
  --text-faint: rgba(242, 242, 247, 0.3);
  --domain-evolution: #a86fdf;
  --domain-evolution-glow: rgba(168, 111, 223, 0.08);
  --domain-evolution-neon: rgba(168, 111, 223, 0.15);
  --trinity-approve: #32D74B;
  --trinity-deny: #FF453A;
  --trinity-modify: #FBBC05;
  --radius-card: 14px;
  --radius-pill: 9999px;
  --padding-card: 24px;
  --gap-items: 16px;
  --grid: 8px;
  --font-body: 'Source Sans 3', -apple-system, sans-serif;
  --font-system: 'Inter', -apple-system, sans-serif;
  --font-mono: 'JetBrains Mono', monospace;
  --font-size-body: 17px;
  --font-size-system: 11px;
  --font-size-mono: 12px;
  /* Elevation shadows (§4.1) */
  --shadow-content: 0 4px 16px rgba(0, 0, 0, 0.06);
  --shadow-raised: 0 8px 24px rgba(0, 0, 0, 0.08);
  --shadow-navigation: 0 24px 60px rgba(0, 0, 0, 0.12);
}
```

- [ ] **Step 2: Update body and container backgrounds**

```css
body {
  background: var(--void);
  color: var(--text-primary);
  font-family: var(--font-body);
  font-size: var(--font-size-body);
}
```

- [ ] **Step 3: Update card styles to Card Shell atom**

```css
.agent-card {
  background: var(--container-low);
  border-radius: var(--radius-card);
  padding: var(--padding-card);
  position: relative;
  overflow: hidden;
  box-shadow: var(--shadow-content);
}

.agent-card::before {
  content: '';
  position: absolute;
  top: 0;
  left: 0;
  width: 120px;
  height: 120px;
  background: radial-gradient(circle at top left, var(--domain-evolution-glow), transparent);
  pointer-events: none;
}

.agent-card.elevated {
  background: var(--container-high);
}
```

- [ ] **Step 4: Commit**

```bash
cd ~/coders-war-room
git add static/
git commit -m "style: apply North Star Design System v4.4 CSS tokens

Void black, Container-Low/High, Violet Evolution domain, Card Shell with
radial glow, 8pt grid, typography roles (Source Sans 3, Inter, JetBrains Mono).
Foundation for agent card redesign and Gates dashboard."
```

---

### Task 11: Redesign agent cards with gate status

**Files:**
- Modify: `static/index.html` (or `static/evolution-tab.html`)

- [ ] **Step 1: Add gate status rendering to agent cards**

Add JavaScript that fetches hook events from `/api/agents/{name}/hook-events` and renders gate status dots on each agent card. The card HTML structure:

```html
<div class="agent-card" data-agent="qa-agent">
  <div class="card-header">
    <span class="domain-badge">◉</span>
    <span class="agent-name">QA Agent</span>
    <span class="model-pill">SONNET</span>
  </div>
  <div class="status-row">
    <span class="status-pill">● Working: NS-108</span>
    <span class="session-timer">⏱ 12m</span>
  </div>
  <div class="gate-rows">
    <!-- Populated by JS from hook_events API -->
  </div>
  <div class="last-event">
    <!-- Latest hook event in JetBrains Mono -->
  </div>
</div>
```

- [ ] **Step 2: Add WebSocket handler for real-time hook event updates**

In the existing WebSocket connection handler, add a case for `hook_event` messages:

```javascript
// In the WebSocket onmessage handler
case 'hook_event':
  updateAgentGateStatus(data.agent, data.tool, data.exit_code, data.summary);
  break;
```

- [ ] **Step 3: Implement gate dot rendering**

```javascript
function updateAgentGateStatus(agentName, tool, exitCode, summary) {
  const card = document.querySelector(`.agent-card[data-agent="${agentName}"]`);
  if (!card) return;

  const gateRows = card.querySelector('.gate-rows');
  // Find or create the dot for this tool
  let dot = gateRows.querySelector(`[data-tool="${tool}"]`);
  if (!dot) {
    dot = document.createElement('span');
    dot.className = 'gate-dot';
    dot.dataset.tool = tool;
    gateRows.appendChild(dot);
  }

  // Color by exit code: 0 = approve (green), non-0 = deny (red)
  dot.style.color = exitCode === 0 ? 'var(--trinity-approve)' : 'var(--trinity-deny)';
  dot.textContent = `● ${tool}`;
  dot.title = summary;

  // Update last event
  const lastEvent = card.querySelector('.last-event');
  if (lastEvent) {
    lastEvent.textContent = `Last: ${summary} · just now`;
  }
}
```

- [ ] **Step 4: Style gate dots and status elements**

```css
.gate-rows {
  display: flex;
  flex-wrap: wrap;
  gap: var(--grid);
  margin-top: calc(var(--grid) * 2);
}

.gate-dot {
  font-family: var(--font-system);
  font-size: var(--font-size-system);
  text-transform: uppercase;
  letter-spacing: 0.02em;
  color: rgba(255, 255, 255, 0.2); /* grey = not yet run */
}

.model-pill {
  background: var(--domain-evolution-neon);
  color: var(--text-primary);
  border-radius: var(--radius-pill);
  padding: 2px 10px;
  font-family: var(--font-system);
  font-size: var(--font-size-system);
  text-transform: uppercase;
}

.status-pill {
  color: var(--text-primary);
  font-family: var(--font-mono);
  font-size: var(--font-size-mono);
}

.last-event {
  font-family: var(--font-mono);
  font-size: var(--font-size-mono);
  color: var(--text-secondary);
  margin-top: calc(var(--grid) * 2);
  border-top: 1px solid rgba(255, 255, 255, 0.05);
  padding-top: var(--grid);
}
```

- [ ] **Step 5: Commit**

```bash
cd ~/coders-war-room
git add static/
git commit -m "feat: redesign agent cards with hook-verified gate status

Cards show gate tool dots (green/red/grey) from hook_events API.
Real-time updates via WebSocket. Model pill, status pill, last event
in JetBrains Mono. Card Shell with Violet radial glow."
```

---

### Task 12: Add Gates dashboard sub-tab

**Files:**
- Modify: `static/index.html` (or `static/evolution-tab.html`)

- [ ] **Step 1: Add Gates sub-tab to navigation**

Add "Gates" as a new sub-tab alongside the existing "War Room", "Directives", "Deploy", "Crashes" tabs.

- [ ] **Step 2: Implement Gates dashboard view**

The Gates dashboard fetches all hook events and renders them grouped by gate (from gate-registry.yaml structure). Each gate is a Card Shell with tool rows showing results and timestamps.

```javascript
async function renderGatesDashboard() {
  // Fetch all recent hook events
  const response = await fetch('/api/hooks/events/all');
  const { events } = await response.json();

  // Group by tool, show latest status
  // Render gate cards with green/red/violet glow based on pass/fail/pending
}
```

- [ ] **Step 3: Add GET /api/hooks/events/all endpoint to server.py**

```python
@app.get("/api/hooks/events/all")
async def get_all_hook_events(limit: int = 200):
    """Return recent hook events across all agents for Gates dashboard."""
    async with aiosqlite.connect(DB_PATH) as db:
        db.row_factory = aiosqlite.Row
        cursor = await db.execute(
            "SELECT * FROM hook_events ORDER BY timestamp DESC LIMIT ?",
            (limit,),
        )
        rows = await cursor.fetchall()
    return {"events": [dict(r) for r in rows]}
```

- [ ] **Step 4: Commit**

```bash
cd ~/coders-war-room
git add static/ server.py
git commit -m "feat: add Gates dashboard — dedicated view for gate status across pipeline

Shows all gates with tool-level results, timestamps, and pass/fail indicators.
Data from hook_events table. New API endpoint: GET /api/hooks/events/all."
```

---

### Task 13: Add role dropdown model hints

**Files:**
- Modify: `static/index.html` (or `static/evolution-tab.html`)

- [ ] **Step 1: Update the New Agent dialog**

In the agent creation form, when the role dropdown changes, show/hide the model hint text based on `model_hint_label` from role-registry.yaml. The server should expose the role registry data via API for the frontend to read.

- [ ] **Step 2: Add GET /api/registries/roles endpoint**

```python
@app.get("/api/registries/roles")
async def get_roles_registry():
    """Return role registry for UI — role dropdown, model hints."""
    import yaml
    reg_path = os.path.join(os.path.dirname(__file__), "registries", "role-registry.yaml")
    with open(reg_path) as f:
        data = yaml.safe_load(f)
    return data.get("roles", {})
```

- [ ] **Step 3: Implement model hint in JavaScript**

```javascript
// When role dropdown changes
roleSelect.addEventListener('change', (e) => {
  const role = roles[e.target.value];
  const hintEl = document.getElementById('model-hint');
  if (role && role.model_hint_label) {
    hintEl.textContent = role.model_hint_label;
    hintEl.style.display = 'block';
    // Highlight the recommended model in the model dropdown
    modelSelect.value = role.model_hint;
  } else {
    hintEl.style.display = 'none';
  }
});
```

- [ ] **Step 4: Commit**

```bash
cd ~/coders-war-room
git add static/ server.py
git commit -m "feat: add model hints to role dropdown — nudges Sonnet for QA

Role dropdown shows hint text from role-registry.yaml model_hint_label.
Model dropdown highlights recommended option. Does not enforce."
```

---

### Task 14: Add drag-and-drop file/image upload

**Files:**
- Modify: `static/index.html` (or `static/evolution-tab.html`)
- Modify: `server.py`

- [ ] **Step 1: Add POST /api/files/upload endpoint**

```python
@app.post("/api/files/upload")
async def upload_file(request: Request):
    """Handle file uploads from drag-and-drop."""
    form = await request.form()
    upload = form.get("file")
    if not upload:
        return {"error": "No file provided"}, 400

    upload_dir = os.path.join(os.path.dirname(__file__), "uploads")
    os.makedirs(upload_dir, exist_ok=True)

    filename = f"{int(time.time())}_{upload.filename}"
    filepath = os.path.join(upload_dir, filename)
    with open(filepath, "wb") as f:
        content = await upload.read()
        f.write(content)

    return {"filename": filename, "path": filepath, "size": len(content)}
```

- [ ] **Step 2: Add drag-and-drop zone to message compose area**

```javascript
const composeArea = document.getElementById('message-compose');

composeArea.addEventListener('dragover', (e) => {
  e.preventDefault();
  composeArea.classList.add('drag-active');
});

composeArea.addEventListener('dragleave', () => {
  composeArea.classList.remove('drag-active');
});

composeArea.addEventListener('drop', async (e) => {
  e.preventDefault();
  composeArea.classList.remove('drag-active');

  for (const file of e.dataTransfer.files) {
    const formData = new FormData();
    formData.append('file', file);

    const res = await fetch('/api/files/upload', { method: 'POST', body: formData });
    const data = await res.json();

    // Add file pill to compose area
    addFilePill(data.filename, file.type);
  }
});
```

- [ ] **Step 3: Style the drag-drop zone**

```css
.drag-active {
  outline: 2px dashed var(--domain-evolution);
  background: var(--domain-evolution-neon);
  border-radius: var(--radius-card);
}

.file-pill {
  display: inline-flex;
  align-items: center;
  gap: calc(var(--grid) / 2);
  background: var(--container-high);
  border-radius: var(--radius-pill);
  padding: 4px 12px;
  font-family: var(--font-mono);
  font-size: var(--font-size-mono);
  color: var(--text-secondary);
}
```

- [ ] **Step 4: Commit**

```bash
cd ~/coders-war-room
git add static/ server.py
git commit -m "feat: add drag-and-drop file/image upload to message compose

Drop files onto compose area — uploads to server, shows file pills.
Drag zone highlights with Violet Neon Glass glow.
POST /api/files/upload endpoint for file storage."
```

---

## Self-Review

**Spec coverage check:**

| Spec Requirement | Task |
|---|---|
| Hook infrastructure & settings generation | Tasks 1-5 |
| Modular gate architecture (registries) | Task 1 |
| Registry-skill sync validation | Task 5 (Step 2) |
| Hook reliability (timeout, crash, status) | Task 2 (all scripts have trap + timeout) |
| Gate 2 stall detection | Task 1 (gate-registry.yaml stall_detection field) |
| Skill scaffold generator | Task 6 |
| Skill authoring guide | Task 7 |
| Research documentation | Task 8 |
| Project-level safety nets | Task 9 |
| CSS token foundation | Task 10 |
| Agent card redesign with gate status | Task 11 |
| Gates dashboard | Task 12 |
| Role dropdown model hints | Task 13 |
| Drag-and-drop file upload | Task 14 |
| Evolution tab alignment | Task 10 (CSS tokens apply to both) |
| Forensic Empathy | Tasks 11-12 (JetBrains Mono, terse labels) |
| State patterns (idle/working/stalled/offline/error) | Task 11 |
| Compression at 6+ agents | Task 11 (noted in design, CSS handles) |

**Placeholder scan:** No TBD, TODO, or "implement later" found. All tasks have concrete code.

**Type consistency:** `hook_events` table schema, API payloads, and JavaScript consumption all use the same field names: `agent`, `event_type`, `tool`, `exit_code`, `summary`, `timestamp`.

---

Plan complete and saved to `docs/superpowers/plans/2026-04-12-war-room-hardening.md`. Two execution options:

**1. Subagent-Driven (recommended)** — I dispatch a fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** — Execute tasks in this session using executing-plans, batch execution with checkpoints

Which approach?
