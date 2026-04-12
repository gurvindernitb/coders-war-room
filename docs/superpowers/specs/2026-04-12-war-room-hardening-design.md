# Coders War Room — Governed Pipeline Hardening
**Date:** 2026-04-12
**Author:** Gurvinder Singh + Claude (brainstorm session)
**Status:** Draft — pending user review
**Approach:** Foundation-First (Gaps → Gates → Skills → UI)

---

## Executive Summary

The Coders War Room is a FastAPI + tmux + WebSocket coordination system for six Claude Code agents building the North Star daemon. After Sprint 6, three systemic problems emerged: agents can bypass quality gates because enforcement is instructional not structural; the pipeline has no single source of truth for which tools belong to which gates and agents; and the web UI provides no visibility into gate status or tool execution.

This spec addresses all three by making the War Room a **registry-driven product**. Every configurable aspect — gates, roles, tools, hooks, skills, budgets — lives in YAML registries. The server, hooks, settings generator, CI generator, skill scaffolder, and UI all read from these registries. Adding a new agent role, a new review tool, or a new gate is a config change, not a code change.

### Research Basis

This design is informed by:
- **MAST study (ArXiv 2503.13657):** 1,642 execution traces, 14 failure modes, 41-86.7% failure rates in unstructured multi-agent systems
- **AgentCoder (ArXiv 2312.13010):** 12% improvement from separating test generation from code generation
- **MetaGPT (ICLR 2024):** SOPs with structured artifacts "significantly reduce logic inconsistencies"
- **Agent Drift Study (ArXiv 2601.04170):** 42% task success reduction from unchecked context drift
- **Perplexity pipeline optimization report:** Comprehensive synthesis of governed pipeline patterns
- **Internal gate accountability research:** Five-agent parallel investigation of Gate 1/2/3 tools and best practices
- **agent-skills-cli baseline scoring:** All 9 existing skills scored, structural gaps identified

Full research documentation: `docs/research/2026-04-12_pipeline-optimization-research.md`

---

## Four Tracks

| Track | Scope | Repos Touched |
|-------|-------|---------------|
| **Track 1: Hook Infrastructure** | Settings generation, SessionStart skill loading, hook-verified events | War Room + Contextualise |
| **Track 2: Modular Gate Architecture** | Registry-driven gates, tools, accountability chains | War Room + Contextualise |
| **Track 3: Skill Generation & Research** | Scaffold generator, skill authoring guide, research documentation | War Room + Contextualise |
| **Track 4: UI/UX Redesign** | Complete visual overhaul per DESIGN.md v4.4, agent cards, Gates dashboard | War Room |

**Sequence:** Foundation-First — Track 1 → Track 2 → Track 3 → Track 4. Each track builds on the previous.

---

## Track 1: Hook Infrastructure & Settings Generation

### Problem

The War Room has three hook scripts in `~/coders-war-room/hooks/` (PreToolUse inbox poll, UserPromptSubmit augmentation, Stop critical message guard) but none are installed in any agent's settings. Agents start with default Claude Code configuration. Quality enforcement is instructional (the skill says "run tests") not structural (a hook prevents stopping without tests passing).

### Design

**Settings generation at onboard time.** When the War Room creates an agent, a new step runs between "create tmux session" and "inject startup prompt": generate `.claude/settings.local.json` in the agent's working directory.

- `.claude/settings.local.json` is gitignored by design — per-session, not committed
- Claude Code merges it over any project-level `.claude/settings.json` automatically
- The server reads the role-registry.yaml and hook-registry.yaml to assemble the correct hooks for this role

**Three hook layers:**

| Layer | Hook | Event | All Agents | Role-Specific |
|-------|------|-------|-----------|---------------|
| Base | session-start.sh | SessionStart | POST online status to War Room API. Auto-invoke role skill. | — |
| Base | check-warroom-inbox.sh | PreToolUse (Bash) | Poll `.inbox/<agent>/` for pending messages. Inject as `additionalContext`. | — |
| Base | stop-guard-warroom.sh | Stop | Check for critical unread War Room messages. Exit 2 blocks stop. | — |
| Engineer | engineer-quality-gate.sh | Stop | — | Run `pytest tests/ -q`. Exit 2 if tests fail. |
| QA | qa-quality-gate.sh | Stop | — | Verify `qa-suite.sh` was executed (check `/tmp/qa-suite-*.json`). Exit 2 if not. |
| Git Agent | verify-qa-before-merge.sh | PreToolUse (Bash) | — | Block `git merge`/`git push main` without `docs/qa/<ID>_review.md` containing `VERDICT: PASS`. |
| Engineer | post-edit-lint.sh | PostToolUse (Edit/Write) | — | Auto-lint modified Python files. Async, no latency penalty. |

**Project-level safety net.** Both project repos (`~/contextualise/` and `~/coders-war-room/`) get a `.claude/settings.json` with baseline hooks (test gate on Stop, merge block on PreToolUse). This catches any Claude Code session working in these repos, whether started from War Room or manually.

**War Room API additions:**

- `POST /api/hooks/event` — Receives hook callback data: `{agent, event_type, tool, exit_code, summary, timestamp}`. Stored in SQLite, broadcast via WebSocket.
- `GET /api/agents/{name}/hook-events` — Returns recent hook events for an agent. UI reads this for agent card gate status.

**SessionStart skill loading.** The SessionStart hook auto-invokes the agent's role skill via the `Skill` tool. The agent doesn't need to remember — the hook fires it. This replaces the current instruction-based approach ("invoke your role skill before anything else") with a structural guarantee.

### Files Changed

| File | Change |
|------|--------|
| `server.py` | New function: `generate_agent_settings()`. Called during agent creation, before Claude Code starts. |
| `server.py` | New endpoints: `POST /api/hooks/event`, `GET /api/agents/{name}/hook-events`. |
| `server.py` | New SQLite table: `hook_events (id, agent, event_type, tool, exit_code, summary, timestamp)`. |
| `hooks/session-start.sh` | New. POSTs online status, invokes role skill. |
| `hooks/engineer-quality-gate.sh` | New. pytest Stop gate. |
| `hooks/qa-quality-gate.sh` | New. qa-suite.sh verification Stop gate. |
| `hooks/post-edit-lint.sh` | New. PostToolUse flake8 on modified files. |
| `hooks/block-code-writes.sh` | New. Denies Write/Edit for non-coding roles. |
| `~/contextualise/.claude/settings.json` | Add project-level safety-net hooks. |

---

## Track 2: Modular Gate Architecture

### Problem

Gate configuration is scattered across `sprint-integration-gate.yml`, `qa-suite.sh`, agent skills, and guardrails.md. Adding a tool means editing five places. There's no single view of which tool belongs to which gate, which agent runs it, and how it's enforced.

### Design

**Four YAML registries in a single directory:**

```
~/coders-war-room/
  registries/
    gate-registry.yaml         # Gates, tools, dispositions, thresholds
    role-registry.yaml         # Agent roles, skills, hooks, model hints
    hook-registry.yaml         # Hook templates, event types, conditions
    tool-budget-registry.yaml  # Budget limits, tracking, alert thresholds
```

### Gate Registry

Defines every gate, every tool within it, and every accountability chain.

```yaml
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
        stall_note: "Cloud deploys are volatile. If deploy hangs past timeout, fail fast — do not let investigating agent idle."
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

### Role Registry

Defines every agent role, its skill, hooks, tools, model hint, and gate accountability.

```yaml
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
```

### Hook Registry

Defines hook templates referenced by role-registry.yaml.

```yaml
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

### Tool Budget Registry

```yaml
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

### Consumers

| Consumer | Reads | Produces |
|----------|-------|----------|
| **Agent creation API** (server.py) | role-registry, hook-registry | `.claude/settings.local.json` per agent |
| **CI generator** (future) | gate-registry (level: sprint) | `sprint-integration-gate.yml` steps |
| **qa-suite.sh generator** (future) | gate-registry (also_runs: per-story) | `scripts/qa-suite.sh` |
| **Skill scaffold generator** | All four registries | SKILL.md scaffolds |
| **UI** | All four registries + hook_events table | Agent cards, Gates dashboard, role dropdown |
| **sprint-gate-protocol skill** | gate-registry | Routing table for agents |
| **Chronicler** | tool-budget-registry + hook_events | Weekly budget snapshot |

### Registry-Skill Sync Validation

**Problem:** If `gate-registry.yaml` is updated (e.g., pip-audit added to Gate 1) but `generate.py --all` hasn't been run, the hooks enforce seven tools while the QA agent's skill still describes six. The agent gets confused — the hook blocks on a tool the skill doesn't mention.

**Solution:** `server.py` startup validation.

At server boot, and before every agent creation, the server compares:
- **Content hashes** (SHA-256) of all four registry files vs hashes stored in `registries/.last-generated.json`
- Hash-based comparison is more reliable than mtime — catches content changes regardless of filesystem timestamp quirks, and ignores no-op touches
- If any registry hash mismatches, the server:
  1. Logs a warning: `"Registry updated since last skill generation. Run: python skill-engine/generate.py --all"`
  2. In **strict mode** (configurable): blocks agent creation with an error message until generation runs
  3. In **lenient mode** (default): allows creation but posts a War Room system message: `[SYSTEM] Registry-skill drift detected. Skills may reference outdated gate/tool assignments.`

The scaffold generator writes a `<!-- REGISTRY VERSION: sha256:abc123 -->` comment at the auto/collaborative boundary in each SKILL.md. Collaborative sessions check this hash against current registries before editing.

This mirrors the `context-spec.yaml → compile.py` discipline: edit the spec, then compile, then deploy.

```python
# Pseudocode for server.py startup check
def validate_registry_sync():
    import hashlib, json
    gen_file = "registries/.last-generated.json"
    last_hashes = json.load(open(gen_file)) if exists(gen_file) else {}
    for reg in ["gate-registry.yaml", "role-registry.yaml", 
                "hook-registry.yaml", "tool-budget-registry.yaml"]:
        current = hashlib.sha256(open(f"registries/{reg}").read().encode()).hexdigest()
        if current != last_hashes.get(reg):
            log.warning(f"{reg} changed since last generation")
            return False
    return True
```

### Hook Reliability (Third-Party Review Findings)

Three failure modes identified by independent review:

**1. Hook timeout orphaning.** If pytest hangs indefinitely inside the engineer Stop hook, the agent session is stuck — can't stop, can't proceed. All hook scripts must handle `SIGTERM` from Claude Code's timeout mechanism gracefully. On timeout: exit 2 with a message ("pytest timed out after 120s — investigate manually") rather than silent death.

**2. Hook crash propagation.** If a hook script crashes (segfault, missing binary, permission error), Claude Code treats it as exit code != 0 and continues. The agent proceeds unchecked. Mitigation: all hook scripts wrap their core logic in a defensive shell pattern:
```bash
#!/bin/bash
set -euo pipefail
trap 'echo "Hook crashed: $0" >&2; exit 2' ERR
# ... core logic ...
```
Exit 2 on crash blocks the agent rather than allowing silent bypass.

**3. Hook status on agent cards.** The UI must show a distinct state for "hook not responding" — separate from "not run" (grey) and "failed" (red). An amber indicator means the hook infrastructure itself needs attention, not just the gate tool.

### Scalability

Adding a new role (e.g., UX Designer):
1. Add entry to `role-registry.yaml`
2. Add any new hook templates to `hook-registry.yaml`
3. Run `skill-engine/generate.py --role ux-designer` to scaffold the SKILL.md
4. Collaborative Claude Code session to finish the skill
5. Done — server reads the role, UI shows it in dropdown, hooks auto-configure

Adding a new gate tool:
1. Add entry to the relevant gate in `gate-registry.yaml`
2. If it has a budget: add entry to `tool-budget-registry.yaml`
3. Run `skill-engine/generate.py --all` to update affected skill scaffolds
4. Done — CI generator picks it up, qa-suite.sh generator picks it up, UI shows it on agent cards

Adding a new gate entirely:
1. Add `gate-4-*` section to `gate-registry.yaml`
2. Lego Verdict reads all gates dynamically — no code change
3. Done

### Timeout Configuration

Tool timeouts live in `gate-registry.yaml` (the `timeout` field on each tool entry), not in hook scripts. The settings generator reads these and injects them as environment variables (e.g., `WARROOM_PYTEST_TIMEOUT=120`) into the agent's settings. Hook scripts read the env var with a fallback default. This means adjusting a timeout is a YAML change — no shell script editing.

### SQLite Concurrency

With 6+ agents POSTing hook events simultaneously, the server must handle SQLite write contention. Configuration:
- **WAL mode** (`PRAGMA journal_mode=WAL`): allows concurrent reads while writes serialize
- **Busy timeout** (`PRAGMA busy_timeout=5000`): retries for 5 seconds on lock instead of instant failure
- This is the same pattern as North Star's `state.py` DatabaseManager

---

## Track 3: Skill Generation & Research Documentation

### Problem

SKILL.md files are hand-written. When a tool is added to `gate-registry.yaml`, someone must remember to update six agent skills manually. The research done today (MAST failure taxonomy, AgentCoder, MetaGPT, skill scoring) exists only in chat history and will be lost.

### Design

**Two components:**

1. **Scaffold generator** — reads registries, produces the obvious 50% of a SKILL.md
2. **Skill authoring guide** — documents today's research so any Claude Code session can finish the nuanced 50%

### Scaffold Generator

**Location:** `~/coders-war-room/skill-engine/generate.py`

**What it produces:** A SKILL.md with two zones separated by a clear boundary:

- **Auto-generated zone** (above the line): gate accountability table, tool assignments, hook enforcement table, War Room signal formats, budget awareness — all derived from registries
- **Collaborative zone** (below the line): role description, session startup, workflow steps, mandatory tools, behavioral rules — authored by human + Claude Code

**The auto-generated zone regenerates when registries change.** The collaborative zone is never overwritten.

**Commands:**

```bash
cd ~/coders-war-room
python skill-engine/generate.py --role qa          # One role
python skill-engine/generate.py --all              # All roles
python skill-engine/generate.py --role ux-designer # New role
python skill-engine/generate.py --diff             # Preview changes
```

**Auto-generated section structure:**

```markdown
## Gate Accountability
<!-- AUTO-GENERATED from gate-registry.yaml — do not hand-edit -->

| Gate | Tools You Run | Disposition | Retry Ceiling | On Fail |
|------|--------------|-------------|---------------|---------|
| Gate 1 | pytest, flake8, mypy, bandit, coverage, secrets | BLOCK | 2 | [GATE-1 FAIL] → Engineer |

## Tool Assignments
<!-- AUTO-GENERATED from role-registry.yaml -->

| Tool | Lane | Budget |
|------|------|--------|
| pytest | All | — |
| QODO CLI | Full Pass only | 30 PRs/month |

## Hook Enforcement
<!-- AUTO-GENERATED from hook-registry.yaml -->

| Hook | Event | What It Does |
|------|-------|-------------|
| qa-stop-gate | Stop | qa-suite.sh must run before stop |

## War Room Signals
<!-- AUTO-GENERATED from gate-registry.yaml -->

| Signal | When |
|--------|------|
| [GATE-1 FAIL] | Routine failure |
| [GATE-1 FAIL | ESCALATE] | Same file fails twice or 30+ min |
| [GATE-1 | HUMAN REQUIRED] | Security, confidence <60% |
```

### Skill Authoring Guide

**Location:** `~/coders-war-room/docs/skill-authoring-guide.md`

**Purpose:** Any Claude Code instance opening a collaborative skill session reads this first. It ensures today's research informs every future skill.

**Contents:**

1. **Methodology — TDD for Skills** (from `superpowers:writing-skills`)
   - RED: Run pressure scenario without the skill. Document baseline failures verbatim.
   - GREEN: Write minimal skill addressing those specific failures.
   - REFACTOR: Close loopholes, add rationalization counters, re-test.
   - Iron Law: No skill without a failing test first.

2. **MAST Failure Modes to Design Against**
   - FM-1.3 Step Repetition (15.7%): Skill must include explicit progress tracking.
   - FM-2.6 Reasoning-Action Mismatch (13.2%): Skill must verify actions match stated plans.
   - FM-1.1 Disobey Task Specification (11.8%): Skill must include red flags table.
   - FM-1.5 Unaware of Termination Conditions (12.4%): Skill must define "done" precisely.
   - FM-3.2/3.3 Verification Failures (17.3%): Skill must require evidence, not claims.

3. **Structural Principles**
   - Separation of duties: QA never sees Engineer's conversation (AgentCoder: 12% improvement).
   - File-based handoffs: Agents read files, not War Room messages, for task data.
   - Hook-verified truth: Agent cards show hook data, not self-reports.
   - Short-lived sessions: Law 7 (Done Means Terminate) prevents context drift (42% success reduction without).

4. **Scoring Protocol**
   - Use `agent-skills-cli` (`skills score`) for every finished skill.
   - Baseline scores: role skills 86-89, foundational skills 72-79.
   - Target: all skills 85+ after improvements.
   - Advanced dimension: add `scripts/` and `references/` where appropriate.

5. **Skill Structure Rules**
   - Description starts with "Use when..." — never summarize the workflow (CSO principle).
   - Under 300 lines for shared skills.
   - Table-driven, not prose — routing tables, signal formats, tool assignments.
   - Auto-generated sections clearly marked — never hand-edit what the registry generates.

6. **Collaborative Session Protocol**
   - Read the scaffold (generated 50%).
   - Read this guide.
   - Work through collaborative sections with Gurvinder.
   - Score with `agent-skills-cli`.
   - Lock in — commit and tag version.

### Research Documentation

**Location:** `~/coders-war-room/docs/research/2026-04-12_pipeline-optimization-research.md`

**Contents:** The Perplexity research document, gate accountability findings, skill audit results, and War Room structural analysis — preserved as reference material. The skill authoring guide points to this. Not duplicated — referenced.

### In-House Skill Tools (Contextualise Project)

Separately from the War Room's scaffold generator, the in-house skill tools in `~/contextualise/` (`skill_manifest.py`, `skill_evaluator.py`, `skill_generator.py`) receive the research findings as documentation so they benefit when they mature. These handle **domain automation skills** (document-filing, sweep-processing). The War Room's scaffold generator handles **agent identity skills** (role SKILL.md files). Two separate concerns.

---

## Track 4: War Room UI/UX Redesign

### Problem

The War Room web UI uses ad-hoc styling that doesn't match the North Star Design System. Agent cards show minimal information with no gate status visibility. The Evolution tab in the North Star iOS app loads this UI via WKWebView — visual inconsistency between the War Room and the rest of the app.

### Design Basis

North Star Master Design System v4.4 (`docs/ux/Stich/DESIGN.md`). The War Room lives in the **Evolution domain** — Violet (`#a86fdf`) is the ambient color.

### Design Token Mapping (SwiftUI → CSS)

| Token | CSS Variable | Value |
|-------|-------------|-------|
| Void | `--void` | `#000000` |
| Container-Low | `--container-low` | `#131313` |
| Container-High | `--container-high` | `#1B1B1B` |
| Ivory text | `--text-primary` | `#F2F2F7` |
| Dimmed White | `--text-secondary` | `rgba(242,242,247,0.6)` |
| Evolution domain | `--domain-evolution` | `#a86fdf` |
| Approve (gate pass) | `--trinity-approve` | `#32D74B` |
| Deny (gate fail) | `--trinity-deny` | `#FF453A` |
| Modify (gate warn) | `--trinity-modify` | `#FBBC05` |
| Card radius | `--radius-card` | `14px` |
| Pill radius | `--radius-pill` | `9999px` |
| Card padding | `--padding-card` | `24px` |
| Grid unit | `--grid` | `8px` |
| Body | `--font-body` | Source Sans 3, 17px |
| System voice | `--font-system` | Inter, 11px bold uppercase |
| Technical | `--font-mono` | JetBrains Mono, 12px |

### Layout

```
┌────────────────────────────────────────────────────────────┐
│  NAV BAR — Container-High + backdrop blur                  │
│  "Coders War Room" (System Voice) + gate status summary    │
├──────────────┬─────────────────────────────────────────────┤
│              │                                             │
│  AGENT       │  MAIN PANEL                                 │
│  PANEL       │                                             │
│  320px       │  Sub-tabs:                                  │
│              │  War Room | Gates | Directives | Deploy     │
│  Redesigned  │                                             │
│  agent cards │  War Room = message feed                    │
│  (scroll)    │  Gates = gate status dashboard (NEW)        │
│              │  Directives/Deploy = dormant (Forge)        │
│              │                                             │
├──────────────┴─────────────────────────────────────────────┤
│  BOTTOM NAV — Floating pill, backdrop blur                 │
│  [ War Room ]  [ Gates ]  [ Files ]                        │
└────────────────────────────────────────────────────────────┘
```

- Max-width 1200px (§12 Web platform rule)
- Mobile: single-view constraint at 768px breakpoint (existing)
- Agent panel: 320px (up from ~240px for redesigned cards)

### Redesigned Agent Cards

Card Shell per design system:
- 14pt radius, Container-Low `#131313`, 24pt padding
- Top-left radial glow: Violet at 8%
- No Liquid Glass on cards (§14)

```
┌───────────────────────────────────────────┐
│ ◉ QA Agent                    SONNET      │
│                                           │
│ ● Working: NS-108              ⏱ 12m     │
│                                           │
│ GATE 1 ────────────────────────────       │
│  ● pytest    ● flake8    ● mypy          │
│  ● bandit    ● coverage  ● secrets       │
│                                           │
│ GATE 3 ────────────────────────────       │
│  ○ coderabbit                             │
│                                           │
│ ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄      │
│ Last: flake8 clean · 2m ago               │
└───────────────────────────────────────────┘
```

- **Gate rows:** Only gates this agent is `gates_accountable_for` appear (from role-registry.yaml)
- **Tool dots:** Green `#32D74B` = passed, Red `#FF453A` = failed, Grey `rgba(255,255,255,0.2)` = not run
- **Data source:** Hook events table — system-verified, not agent self-reports
- **Model pill:** Status Pill atom, 9999px radius
- **Last event:** JetBrains Mono 12pt, dimmed white

**State patterns (§11):**

| State | Appearance |
|-------|-----------|
| Online, idle | Container-Low, "Idle", grey gate dots |
| Online, working | Container-High (elevated), story ID in status pill, live gate dots |
| Stalled | Amber beacon dot pulses. "Stalled · 5m" |
| Offline | Card dims to 40% opacity. Gate dots frozen at last state |
| Error | Red beacon dot. Plain language description |

**Compression (§17):** At 6+ agents, cards compress to: name + status pill + three summary dots (Gate 1/2/3). Click to expand.

### Gates Dashboard (New Sub-Tab)

Dedicated view showing gate status across the pipeline. Each gate is a Card Shell:

- Pass: top-left glow Green at 8%
- Fail: top-left glow Red at 8%
- Pending: top-left glow Violet at 8%
- Tool rows: JetBrains Mono, with result + timestamp
- Data source: hook_events SQLite table + CI artifact data

### Role Dropdown

Agent creation dialog shows model hint from `role-registry.yaml`:

- When QA is selected: hint text appears below — "Sonnet recommended — independent judgment from Engineer's Opus"
- Model dropdown highlights recommended option but does not enforce
- Hint text comes from `model_hint_label` field — roles without a hint show nothing

### Drag-and-Drop File/Image Upload

- Drop zone on message compose area
- Dragover highlight: Violet glow (Neon Glass Protocol — 15% violet bg)
- Supported: images (inline thumbnail), text files (content injected), PDFs (thumbnail + filename)
- `POST /api/files/upload` — stored locally, referenced in message
- Attached files shown as small pills below text input before sending
- Works alongside existing file viewer drag-to-chat — both pathways valid

### Forensic Empathy (§3.1)

| Current | Redesigned |
|---------|-----------|
| "Agent is currently working on task" | "Working: NS-108 · 12m" |
| "All tests have passed successfully" | "pytest: 1242 passed" |
| "The agent seems to be stalled" | "Stalled · 5m" |
| "No agents are currently online" | Empty: icon (48pt white/20) + "No agents online" |
| "Connection lost to server" | Red beacon + "Connection lost. Reconnecting." |

### Evolution Tab Alignment

The War Room at `localhost:5680` is what the Evolution tab loads via WKWebView. The redesign applies to both:

- CSS tokens mirror DESIGN.md exactly — feels native inside North Star app
- Existing card color `#1C1C1E` updates to `#131313` / `#1B1B1B` (Container-Low/High)
- Sub-tabs stay: War Room | **Gates** (new) | Directives | Deploy | Crashes
- Mobile responsive at 768px (existing breakpoint preserved)

---

## Success Criteria

The hardening is complete when:

1. **Hooks deploy automatically.** Onboarding an agent produces `.claude/settings.local.json` with role-appropriate hooks. No manual configuration.
2. **Engineer cannot stop with failing tests.** The Stop hook structurally prevents it.
3. **QA cannot report PASS without running qa-suite.sh.** The Stop hook verifies.
4. **Git Agent cannot merge without QA PASS.** PreToolUse hook blocks it.
5. **Agent cards show hook-verified gate status.** Not agent self-reports.
6. **Adding a role is a config change.** New YAML entry + scaffold generation + collaborative session. No server code changes.
7. **Adding a gate tool is a config change.** New YAML entry. CI, qa-suite.sh, agent cards, and skill scaffolds update from registry.
8. **Model hint appears for QA.** Role dropdown nudges Sonnet selection.
9. **UI matches Design System v4.4.** Void black, Container-Low cards, Violet domain, Forensic Empathy, 8pt grid.
10. **Drag-and-drop file/image upload works.** Directly onto message compose area.
11. **Gates dashboard exists.** Dedicated view showing all gate/tool status across pipeline.
12. **Skill authoring guide is documented.** Today's research preserved and accessible.
13. **Scaffold generator produces 50% of any new skill.** From registries, with clear boundary for collaborative zone.

---

## Out of Scope

- **In-house skill compiler** (`compile.py`, `skill_manifest.py`) — the house we're still building. Receives research documentation but no code changes.
- **Agent Teams migration** — experimental feature, premature.
- **Haiku model tiering** — conflicts with Scout's actual workload.
- **Forge pipeline** — Directives, Deploy, Crashes sub-tabs stay dormant.
- **iOS SwiftUI implementation** of Evolution tab — WKWebView wrapper is a separate ticket.

---

*Design produced via superpowers:brainstorming. Research basis: MAST (ArXiv 2503.13657), AgentCoder (ArXiv 2312.13010), MetaGPT (ArXiv 2308.00352), Agent Drift (ArXiv 2601.04170), Perplexity pipeline optimization report, internal gate accountability research, agent-skills-cli baseline scoring.*
