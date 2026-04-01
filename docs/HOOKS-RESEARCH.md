# Claude Code Hooks Research: War Room Message Delivery

**Researcher:** Claude Code (Opus 4.6)
**Date:** 2026-03-31
**Status:** Complete
**Verdict:** Hooks provide a VIABLE but INDIRECT solution. Not spontaneous push delivery, but reliable poll-on-every-action delivery with <100ms latency.

---

## 1. What Claude Code Hooks Are

Hooks are shell commands, HTTP calls, prompt evaluations, or agent evaluations that execute at specific lifecycle points during a Claude Code session. They are configured in `settings.json` (user-global, project, or project-local) and fire automatically when their trigger event occurs.

They are NOT plugins, NOT MCP servers, and NOT background processes. They are reactive: something happens, then the hook fires.

## 2. All Hook Event Types

There are approximately 25 lifecycle events. The ones relevant to war room delivery are marked with arrows.

| Event | When It Fires | Can Block? | Stdout Visible to Claude? |
|-------|---------------|:----------:|:-------------------------:|
| `SessionStart` | Session begins or resumes | No | **YES** -- added as context |
| **--> `UserPromptSubmit`** | User submits a prompt, before processing | Yes (exit 2) | **YES** -- added as context |
| **--> `PreToolUse`** | Before any tool execution | Yes (exit 2) | Only via JSON hookSpecificOutput |
| `PermissionRequest` | Permission dialog appears | Yes | No |
| **--> `PostToolUse`** | After tool succeeds | No | **NO** -- stderr only on exit 2 |
| `PostToolUseFailure` | After tool fails | No | No |
| **--> `Notification`** | Claude sends a notification | No | No (stderr in verbose only) |
| `SubagentStart` | Subagent spawned | No | No |
| `SubagentStop` | Subagent finishes | Yes | No |
| `TaskCreated` | Task created | Yes | No |
| `TaskCompleted` | Task marked complete | Yes | No |
| **--> `Stop`** | Agent finishes responding | Yes (exit 2) | stderr fed to Claude on block |
| `StopFailure` | Turn ends due to API error | No | Ignored entirely |
| `TeammateIdle` | Team member about to idle | Yes | No |
| `PreCompact` | Before context compaction | No | No |
| `PostCompact` | After compaction | No | No |
| `ConfigChange` | Config file changes | Yes | No |
| `CwdChanged` | Working directory changes | No | No |
| `FileChanged` | Watched file changes on disk | No | No |
| `InstructionsLoaded` | CLAUDE.md loaded | No | No |
| `Elicitation` | MCP server requests input | Yes | No |
| `WorktreeCreate` | Worktree created | Yes | No |
| `WorktreeRemove` | Worktree removed | No | No |
| `SessionEnd` | Session terminates | No | No |

## 3. How Hook Output Reaches Claude

This is the critical question for message delivery.

### Exit Code Semantics

| Exit Code | Meaning | What Claude Sees |
|-----------|---------|------------------|
| 0 | Success | JSON parsed for structured output. Plain text: shown only in verbose mode EXCEPT for SessionStart and UserPromptSubmit where it IS added as context. |
| 2 | Blocking error | **stderr is fed to Claude as an error message.** The action is blocked. Claude must respond to the error. |
| Other | Non-blocking error | stderr shown in verbose mode only. Execution continues. |

### The Three Context Injection Paths

**Path A: SessionStart / UserPromptSubmit stdout (exit 0)**
- Plain text stdout is added directly to Claude's context.
- Claude sees it as additional information alongside the user's prompt.
- This is the cleanest injection path.

**Path B: PreToolUse JSON output (exit 0)**
- Can return `hookSpecificOutput` with `additionalContext` field.
- Claude sees this context when deciding whether to proceed with the tool.
- Can also return `permissionDecision: "deny"` with a reason.

**Path C: Any blocking hook stderr (exit 2)**
- stderr is fed to Claude as an error message.
- Claude is forced to acknowledge and respond to it.
- The blocked action does not execute.
- This is the "loudest" injection -- Claude MUST deal with it.

### What Does NOT Reach Claude

- PostToolUse stdout (exit 0) -- only shown in verbose mode
- Notification hook output -- stderr in verbose mode only
- Any non-blocking error (exit 1, 3, etc.) -- stderr in verbose mode only
- FileChanged hook output -- no context injection

## 4. Can Hooks Fire on a Timer/Interval?

**NO.** Hooks are strictly event-driven. There is no cron, interval, or polling mechanism built into the hooks system.

However, hooks fire on EVERY tool use. In a typical Claude Code session, tool calls happen every few seconds. This means:
- `PreToolUse` fires before every Bash, Read, Write, Edit, Grep, Glob call
- `PostToolUse` fires after every successful tool call
- `UserPromptSubmit` fires every time the user (or pasted text) submits input

For an active agent, tool calls happen frequently enough that "check on every tool use" approximates "check every few seconds."

## 5. Can Hooks Solve the War Room Delivery Problem?

### The Core Challenge Restated

War room messages arrive via tmux paste. Claude Code treats them as low-priority user input and responds "Noted." We need messages to arrive as system-level context that Claude cannot dismiss.

### Strategy: PreToolUse Inbox Check

The most promising approach uses a `PreToolUse` hook that:
1. Fires before EVERY tool call (Bash, Read, Write, Edit, etc.)
2. Checks a local inbox file for unread war room messages
3. If messages exist, returns them via `hookSpecificOutput.additionalContext`
4. Claude sees the messages as system context attached to the tool call
5. The tool call proceeds normally (exit 0, no blocking)

**Why this works:**
- Fires constantly during active work (every few seconds)
- Context injection via `additionalContext` is visible to Claude
- Does not block or disrupt the workflow
- Messages arrive as system context, not user input
- Claude cannot "Noted." away system context

**Why this is not perfect:**
- Only fires when Claude is actively using tools
- If Claude is generating a long response without tool calls, there is a gap
- The `additionalContext` injection on PreToolUse (exit 0) may be lower priority than we want

### Strategy: Stop Hook Forced Continuation

A more aggressive approach uses the `Stop` hook:
1. When Claude finishes responding and is about to stop, the hook fires
2. The hook checks for unread war room messages
3. If messages exist, it exits with code 2 and writes the messages to stderr
4. Claude is FORCED to continue -- it cannot stop until it addresses the stderr
5. Claude sees the war room messages as an error it must respond to

**Why this works:**
- Claude literally cannot stop until it processes the messages
- stderr on exit 2 is the loudest injection path
- Forces immediate acknowledgment

**Why this is risky:**
- Can cause infinite loops if not carefully guarded (stop blocked -> Claude responds -> tries to stop -> blocked again)
- Must check `stop_hook_active` field to prevent recursion
- Feels like fighting the system rather than working with it
- Messages arrive as "errors" which may confuse the agent's reasoning

### Strategy: UserPromptSubmit Context Injection

When the tmux paste delivers a war room message, the `UserPromptSubmit` hook fires:
1. Hook examines the incoming prompt text
2. If it contains `[WARROOM]`, the hook rewrites/augments it
3. stdout is added as context that Claude sees alongside the message
4. The hook could prepend: "SYSTEM ALERT: The following is a high-priority war room message that requires immediate attention and a substantive response."

**Why this works:**
- Intercepts the exact moment of message delivery
- Can augment the pasted text with system-level framing
- stdout from UserPromptSubmit IS added as context

**Why this is limited:**
- Only fires on the paste itself -- if Claude still "Noted."s it, we are back to square one
- The augmented context may help but is not guaranteed to override Claude's "stay focused" behavior

### RECOMMENDED: Combined Strategy

Use ALL THREE hooks together:

1. **UserPromptSubmit** -- When a war room message is pasted, augment it with system-level framing to reduce "Noted." dismissals.

2. **PreToolUse** -- On every tool call, check the inbox file. If there are unread messages, inject them as `additionalContext`. This is the persistent poll that ensures messages are seen even if the paste was dismissed.

3. **Stop** (with guard) -- As a last resort, if there are CRITICAL unread messages when Claude tries to stop, block the stop and force it to address them. Use sparingly and with recursion guards.

## 6. Prototype Configuration

### settings.json Addition

```json
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "/Users/gurvindersingh/coders-war-room/hooks/augment-warroom-paste.sh",
            "timeout": 2
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "/Users/gurvindersingh/coders-war-room/hooks/check-warroom-inbox.sh",
            "timeout": 2
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "/Users/gurvindersingh/coders-war-room/hooks/stop-guard-warroom.sh",
            "timeout": 2
          }
        ]
      }
    ]
  }
}
```

### Hook Scripts

See the prototype scripts in `/Users/gurvindersingh/coders-war-room/hooks/`:
- `check-warroom-inbox.sh` -- PreToolUse inbox checker
- `augment-warroom-paste.sh` -- UserPromptSubmit message augmenter
- `stop-guard-warroom.sh` -- Stop hook for critical messages

## 7. The Inbox File Protocol

The hooks read from a simple file-based inbox:

```
/Users/gurvindersingh/coders-war-room/.inbox/<agent-name>/
  |- msg-<timestamp>.json    # One file per unread message
```

The war room server writes message files here instead of (or in addition to) tmux paste.
The hooks read and delete (or mark read) the files after injection.
This decouples delivery from tmux entirely.

## 8. Latency Analysis

| Component | Latency |
|-----------|---------|
| Hook script startup (bash) | ~5-10ms |
| File existence check (stat) | ~1ms |
| Read small JSON file | ~1ms |
| JSON output construction (jq) | ~5ms |
| **Total per hook invocation** | **~15-20ms** |

This is well under the 100ms target. The hook timeout is set to 2 seconds as a safety net, but actual execution will be ~20ms.

The real latency is not the hook itself but the TIME BETWEEN HOOK FIRES:
- During active tool use: 1-5 seconds between PreToolUse fires
- During long responses: could be 10-30 seconds with no tool calls
- During idle (waiting for user input): UserPromptSubmit fires on next input

## 9. Limitations and Risks

### Confirmed Limitations
1. **No timer-based hooks.** Cannot push messages on a schedule. Must wait for an event.
2. **PostToolUse stdout is not visible to Claude.** Cannot inject context after a tool runs.
3. **FileChanged hook does not inject context.** Even if we watch the inbox folder.
4. **Hooks cannot modify the user's input text.** UserPromptSubmit can ADD context but not rewrite.
5. **PreToolUse additionalContext priority is unclear.** May be treated as low-priority information.
6. **Stop hook risks infinite loops.** Must implement recursion guard carefully.
7. **No hook for "Claude is thinking."** Cannot inject during response generation.

### Risks
1. **Performance degradation** -- If the inbox check script is slow or the inbox has many files, every tool call gets slower.
2. **JSON parsing errors** -- Shell profile output or script errors can corrupt JSON, causing hooks to fail silently.
3. **Infinite stop loop** -- A bug in the stop guard could prevent Claude from ever finishing.
4. **Context pollution** -- Injecting war room messages into every tool call could confuse Claude's reasoning about the tool itself.
5. **Hook conflicts** -- If other hooks are added later, ordering and interaction effects are undocumented.

### Mitigations
- Keep scripts minimal and fast (bash, not Python)
- Use `set -euo pipefail` in all scripts
- Implement a "last checked" timestamp to avoid re-injecting the same messages
- The stop guard should only fire for messages tagged `priority: critical`
- Test thoroughly with the protocol in BUG-001

## 10. Recommendation

**Hooks are the right mechanism, but they deliver poll-based injection, not spontaneous push.**

The combined strategy (UserPromptSubmit + PreToolUse + Stop guard) provides:
- Message visibility within 1-5 seconds during active tool use
- Guaranteed delivery on next user input via UserPromptSubmit
- Last-resort forced acknowledgment via Stop hook for critical messages

This is a significant upgrade over the current "Noted." failure mode:
- Messages arrive as system context, not user input
- Claude cannot dismiss them with "Noted."
- The mechanism is invisible to the user (no tmux paste artifacts)
- The inbox file protocol decouples delivery from tmux entirely

**What hooks will NOT give us:**
- True real-time push during response generation (no hook fires during thinking)
- Sub-second guaranteed delivery (depends on tool call frequency)
- A way to interrupt Claude mid-thought with an urgent message

**For true push delivery, MCP server notifications remain the only theoretical path** -- but it is unclear whether Claude Code surfaces MCP notifications in active conversation context. That would require separate investigation.

**Next step:** Implement the prototype scripts and test with the BUG-001 test protocol.

---

## Sources

- [Claude Code Hooks Reference (Official)](https://code.claude.com/docs/en/hooks)
- [Claude Code Hooks: PreToolUse, PostToolUse & All 12 Events (Pixelmojo)](https://www.pixelmojo.io/blogs/claude-code-hooks-production-quality-ci-cd-patterns)
- [Claude Code Hooks Tutorial: 5 Production Hooks (Blake Crosley)](https://blakecrosley.com/blog/claude-code-hooks-tutorial)
- [Claude Code Hooks Complete Guide (SmartScope)](https://smartscope.blog/en/generative-ai/claude/claude-code-hooks-guide/)
- [Claude Code Hooks: A Practical Guide (DataCamp)](https://www.datacamp.com/tutorial/claude-code-hooks)
