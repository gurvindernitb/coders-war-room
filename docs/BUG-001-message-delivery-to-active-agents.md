# BUG-001: War Room Messages Not Reaching Active Agents

**Status:** Open — needs architectural fix
**Severity:** High — breaks the core value proposition for pre-existing agents
**Discovered by:** Supervisor (Planner session) during live testing with Gurvinder
**Date:** 2026-04-01

---

## The Problem

War room messages are delivered but never seen by agents that are already in an active conversation. The agent's own Claude Code instance silently dismisses them.

## Who Is Affected

| Agent Type | Receives Messages? | Responds? | Why |
|-----------|:---:|:---:|-----|
| Freshly onboarded (idle) | Yes | Yes | No competing conversation. Pasted text IS their conversation. |
| Pre-existing (in active conversation) | Delivered but dismissed | Says "Noted." silently | Claude Code treats pasted text as low-priority side input. Main conversation takes precedence. |

**The supervisor is always affected** because it's always in conversation with Gurvinder. Any agent that was started manually, built context, loaded plugins, and THEN joined the war room will have the same problem.

## Root Cause

The delivery mechanism (`tmux set-buffer` → `paste-buffer` → `send-keys Enter`) successfully injects text into the Claude Code TUI. Claude Code receives it as a new user turn. But when the instance is already in a conversation:

1. The pasted text arrives between exchanges
2. Claude Code processes it as a user message
3. It sees `[WARROOM] phase-1: some message` — which doesn't match the current task context
4. It responds `"Noted."` and returns to the main conversation
5. This exchange happens entirely within the TUI
6. The agent (the conversation partner) never sees it surface in their active thread

**The agent's own Claude instance is acting as a filter.** It's doing exactly what a good assistant should do — staying focused on the current task and not getting distracted. But that "good behaviour" is the bug.

## Evidence

Captured from the supervisor's tmux pane after multiple messages were sent:

```
❯ [WARROOM @supervisor] gurvinder: Do you know why we cannot believe the atoms? Because they make things up.
⏺ Noted.

❯ [WARROOM @supervisor] phase-4: Ha! Good one, Gurvinder. Atoms — can't trust 'em.
⏺ Noted.

❯ [WARROOM @supervisor] test-debug: DEBUG: testing delivery pipeline
⏺ Noted.
```

Every message delivered. Every message processed. Every message dismissed with "Noted." None surfaced to the active conversation.

Server-side verification:
- `check_agent_ready()` returns `True` for supervisor
- `presence=active`, `in_room=True`
- All three subprocess calls (`set-buffer`, `paste-buffer`, `send-keys`) return rc=0
- The pipeline is working perfectly — the wrong thing is happening at the destination

## Why This Matters

Gurvinder's workflow is:

```
1. Start Claude Code session manually
2. Load startup.md, superpowers plugin, build project context
3. Work on tasks, build understanding
4. THEN join the war room when ready to coordinate
```

This means every agent that matters most (the ones with rich context) will be in an active conversation when they join. The war room only works for agents that were born into it with nothing else to do.

**If this isn't fixed, the war room can only coordinate disposable agents, not valuable ones.**

## What Won't Work

- **Pasting louder** — The mechanism works. Claude Code just doesn't care.
- **Prefixing with "IMPORTANT"** — Claude Code doesn't prioritise pasted text by content.
- **Pasting during "idle" detection** — The agent IS idle (at the prompt). Claude Code still treats it as side input when there's an active conversation in context.

## Approaches to Investigate

### Approach 1: Claude Code Hooks

Claude Code supports hooks in `~/.claude/settings.json` — shell commands that execute on events like `PreToolUse`, `PostToolUse`, `Notification`, etc.

**Idea:** A hook that runs after every tool call (or on a timer) that checks for unread war room messages and injects them into the conversation context as a system-level notification rather than a user turn.

**Research needed:**
- What hook events does Claude Code support?
- Can a hook inject text into the conversation context (not the input field)?
- Can a hook return output that Claude Code treats as a system message rather than user input?
- What's the latency? (hooks that run after every tool call need to be <100ms)

Read: https://docs.anthropic.com/en/docs/claude-code/hooks (or check `/Users/gurvindersingh/.claude/settings.json` for examples)

### Approach 2: User-Prompt-Submit Hook

Claude Code has a `UserPromptSubmit` hook that fires when the user submits a message. If we can make a hook fire BEFORE the agent processes the input, the hook could check for war room messages and prepend them to the conversation.

**Research needed:**
- Does `UserPromptSubmit` hook exist and what's its interface?
- Can it modify the input before Claude Code processes it?

### Approach 3: Notification via the Statusline

Claude Code has a configurable statusline (already configured in this project). Could we inject war room notification counts into the statusline? The agent would see "3 unread war room messages" in its status bar and know to check.

**Research needed:**
- Can the statusline script access external state (e.g., an inbox file)?
- Does the agent "see" its own statusline, or is it just visual for the user?

### Approach 4: MCP Server for War Room

Create a lightweight MCP server that the war room exposes. Claude Code agents connect to it. Messages arrive as MCP notifications/resources rather than pasted text.

**Research needed:**
- Can MCP servers push notifications to Claude Code?
- Would Claude Code surface MCP notifications in the conversation?
- Is this overkill vs the hook approach?

### Approach 5: Instruction-Based Protocol (Low-Tech Fallback)

Include in every agent's onboarding/CLAUDE.md:

```
MANDATORY: After EVERY response you give, run:
~/coders-war-room/warroom.sh inbox
If there are unread messages, process them before continuing.
```

This is the "Toyota solution" — no fancy mechanism, just discipline. The agent checks its inbox after every turn. Latency is one turn (seconds, not minutes).

**Pros:** Works immediately, no code changes.
**Cons:** Relies on the agent following instructions (it might forget under context pressure). Adds latency (one full turn before seeing messages).

## Recommended Investigation Order

1. **Approach 5 first** — test if instruction-based polling works reliably. Zero engineering cost.
2. **Approach 1 (hooks)** — if Approach 5 is unreliable, research Claude Code hooks. This is the proper architectural fix.
3. **Approach 4 (MCP)** — if hooks can't inject into conversation context, MCP might be the right layer.
4. **Approaches 2-3** — investigate as needed.

## How to Test Any Fix

1. Start a Claude Code session manually
2. Have a multi-turn conversation with it (build context, make it "busy" with a topic)
3. Join the war room via `join.sh`
4. Send a message from another agent or from the web UI
5. **Success:** The agent surfaces the message in its conversation and responds substantively (not "Noted.")
6. **Failure:** The message is dismissed or never seen

---

*This bug report should be read by the builder agent working on the war room. Use `/superpowers:systematic-debugging` to investigate the approaches above.*
