# M2: Mobile Agents View + Identity System — Design Spec

**Date:** 2026-04-03
**Package:** M2 (second of 4 mobile polish packages)
**Scope:** Agent identity system (web + mobile) + mobile agents tab redesign
**Files:** `static/index.html` (CSS + JS + HTML), `server.py` (SQLite schema + API)

---

## Context

The Agents tab on mobile currently shows desktop-style cards stacked vertically — shrunken desktop view, not a native mobile experience. All agents except supervisor show the same grey color. No avatars. No way to customize agent identity.

This spec defines:
1. A color + avatar identity system with role-based defaults and user overrides
2. A mobile-optimized agent card layout with elongated rounded cards
3. Agent action bottom sheets for mobile interaction

Desktop layout is NOT modified except for additive changes (color picker + icon picker in the creation form, new SQLite columns).

---

## 1. Color Palette

16 preset colors. Role-based defaults with user override capability.

### Role defaults

| Role keyword(s) | Default color | Hex |
|-----------------|--------------|-----|
| supervisor, lead, director | Purple | #b388ff |
| engineer, builder, developer, coder, dev | Blue | #448aff |
| scout, researcher, investigator | Cyan | #18ffff |
| qa, q-a, quality, tester, validator | Red | #ff5252 |
| git, git-agent, vcs | Gold | #ffd740 |
| chronicler, observer, logger | Pink | #ff80ab |
| operator (gurvinder) | Orange | #ff9100 |
| unassigned / fallback | Grey | #7a8a9e |

### Additional swatches (for custom agents)

| Name | Hex |
|------|-----|
| Teal | #64ffda |
| Lime | #b9f6ca |
| Coral | #ff6e40 |
| Indigo | #8c9eff |
| Amber | #ffcc80 |
| Mint | #84ffff |
| Salmon | #f48fb1 |
| Lavender | #ce93d8 |

### Storage

`agents` SQLite table — two new nullable columns:
- `color TEXT` — hex value (e.g., "#448aff"). NULL = use role-based default.
- `icon TEXT` — icon key name (e.g., "wrench"). NULL = use role-based default.

### Color resolution order

1. If `agent.color` is set in SQLite → use it
2. Else → match agent name against role keywords → use default
3. Else → hash-based pick from the 8 additional swatches

This replaces the current `COLORS` dict + `COLOR_PALETTE` system in server.py. The `get_agent_color()` function is updated to check SQLite first.

---

## 2. Avatar Icon Library

Phosphor duotone SVGs embedded as a JavaScript object (`AVATAR_ICONS`). Each icon is an SVG path string. White icon rendered on the agent's color circle.

### Full icon library (25 icons)

| Key | Icon name | Roles it covers |
|-----|-----------|----------------|
| `crown` | Crown | supervisor, lead, director |
| `wrench` | Wrench | engineer, builder, developer |
| `magnifying-glass` | MagnifyingGlass | scout, researcher, investigator |
| `shield-check` | ShieldCheck | qa, quality, tester, validator |
| `git-branch` | GitBranch | git-agent, git, vcs |
| `notebook` | Notebook | chronicler, observer, logger |
| `terminal` | Terminal | operator, admin, root |
| `robot` | Robot | agent (generic fallback) |
| `lightning` | Lightning | runner, executor, dispatcher |
| `brain` | Brain | planner, strategist, architect |
| `bug` | Bug | debugger, fixer |
| `rocket` | Rocket | deployer, release |
| `lock` | Lock | security, auth |
| `database` | Database | data, storage, db |
| `globe` | Globe | api, integration, external |
| `megaphone` | Megaphone | announcer, broadcaster |
| `eye` | Eye | monitor, watcher |
| `palette` | Palette | designer, frontend, ui |
| `book` | Book | docs, writer, documentation |
| `users` | Users | team, group, coordinator |
| `heartbeat` | Heartbeat | health, status, uptime |
| `gauge` | Gauge | performance, metrics |
| `code` | Code | coder, dev (alias for engineer) |
| `clipboard` | Clipboard | reviewer, auditor |
| `gear` | Gear | config, settings, ops |

### Icon resolution order

1. If `agent.icon` is set in SQLite → use it
2. Else → match agent name against role keywords → use default
3. Else → `robot` (generic fallback)

### SVG rendering

Icons are rendered as inline SVGs inside a colored circle:
```html
<div class="agent-avatar" style="background: #448aff">
  <svg><!-- Phosphor duotone path --></svg>
</div>
```

The SVG is white (`fill: white` or `stroke: white`), 22px inside a 40px circle on mobile, 28px inside a 36px circle on desktop sidebar.

---

## 3. Desktop Changes (Additive Only)

### Creation form

The existing "+ new" drawer gets two new fields:

**Color picker:** a row of 16 color swatches (circles, 28px diameter). Tapping one selects it (checkmark overlay). Pre-selected based on role_type entered. Label: "Color".

**Icon picker:** a 5x5 grid of icons (40px cells). Tapping one selects it (highlight border). Pre-selected based on role_type entered. Label: "Icon".

Both are optional — if not selected, role-based defaults are used.

### Agent cards (desktop sidebar)

Add a small avatar circle (28px) to the left of the agent name in each card. Uses the same color + icon system. The colored left border on desktop cards is replaced by the avatar circle.

### API changes

`POST /api/agents/create` — add optional fields: `color` (hex string), `icon` (key string)
`GET /api/agents` — response includes `color` and `icon` for each agent
`PATCH /api/agents/{name}` — new endpoint to update color/icon (used by future mobile edit)

---

## 4. Mobile Agent Cards

### Card design

```
┌──────────────────────────────────────────────────┐
│                                                  │
│   (●WR●)    engineer            ● active         │
│             Implementation       12m             │
│                                                  │
└──────────────────────────────────────────────────┘
```

- **Avatar:** 40px circle, agent's color background, white Phosphor duotone icon centered
- **Name:** 15px, Source Sans 3, bold, agent's color
- **Role:** 13px, Source Sans 3, `var(--text-dim)`, single line, truncated with ellipsis
- **Presence dot:** 8px circle, color matches presence state (green/yellow/cyan/grey)
- **Status word:** 11px, JetBrains Mono, matches presence color
- **Time:** 11px, JetBrains Mono, `var(--text-dim)` — minutes since last activity change
- **Card:** full-width, border-radius 14px, `var(--bg-card)` background, vertical padding 12px, no border-left
- **Card height:** auto, approximately 64px
- **Card gap:** 8px between cards

### Gurvinder (operator) card

- Top of the list, always
- Orange avatar circle with terminal icon
- No action on tap (operator doesn't need agent actions)
- Slightly different background: `var(--bg-elevated)`

### Agent ordering

1. Gurvinder (operator) — always first
2. Active agents — sorted by: active > busy > typing > session
3. Offline agents — at bottom, card opacity 0.6

### Tap action

Tapping an agent card opens a bottom sheet:

```
  ENGINEER
  ─────────────────────
  (chat icon)     Message
  (eye icon)      View Activity
  (info icon)     Details
  ─────────────────────
  Cancel
```

- **Message:** sets `$target` to this agent, updates `$inputTarget` label, switches to Chat tab, focuses input
- **View Activity:** opens a second bottom sheet showing: presence, current tool, current file, last commit message, working directory
- **Details:** opens a second bottom sheet showing: role description, instructions file, model, directory
- **No Remove on mobile** — destructive actions stay on desktop

### Header bar

- "AGENTS" title left-aligned
- Agent count badge (e.g., "9 / 9") — same as current
- "+ new" button — same as current, opens full-screen drawer

---

## 5. What Does NOT Change

- Desktop sidebar layout (except additive avatar circle)
- Desktop agent card structure (additive, not replacement)
- Mobile tab bar, chat view, file view (M1, M3 scope)
- Agent creation flow (only adds color/icon pickers, doesn't change existing fields)
- WebSocket protocol, message format, warroom.sh
- Server startup sequence, reconciliation, persistence logic (except schema addition)

---

## 6. No-Regression Guardrails

- All mobile CSS changes inside `@media (max-width: 767px)`
- SQLite columns are `ALTER TABLE ADD COLUMN` with NULL default — no migration needed, existing data preserved
- Desktop `renderAgents()` function enhanced, not replaced — avatar is prepended to existing card HTML
- The `get_agent_color()` function maintains backward compatibility — if no SQLite color, falls back to current behavior
- Color picker and icon picker in creation form are optional fields — form works without them

---

## 7. Success Criteria

1. Each agent has a colored circular avatar with a Phosphor duotone icon
2. Color defaults match role type (engineers blue, QA red, supervisor purple, etc.)
3. Color and icon can be selected during agent creation on desktop
4. Color and icon persist across server restarts (SQLite)
5. Mobile agent cards show: avatar, name (colored), role, presence, time
6. Tapping a mobile card opens action bottom sheet (Message, View Activity, Details)
7. Agent list ordered: operator first, then by presence state
8. Offline agents dimmed (opacity 0.6)
9. Desktop layout unchanged except additive avatar circles
10. Zero regressions — all existing functionality preserved
