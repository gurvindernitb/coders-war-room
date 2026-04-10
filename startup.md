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

## War Room Communication Standard — Signal Only

Every message you post to the War Room MUST follow this format. No prose. No explanations. No summaries. Signal only.

**Required signals (use exactly these strings):**

| Event | Post format |
|-------|-------------|
| Session start | `[ROLE] online — working: <STORY-ID>` |
| Work begins | `[ROLE] START: <STORY-ID> — <one-line task>` |
| Blocker | `[ROLE] BLOCKED: <STORY-ID> — <reason> @supervisor` |
| Work complete | `[ROLE] DONE: <STORY-ID> — <one-line outcome>` |
| QA trigger | `READY-FOR-QA: <STORY-ID>` |
| QA verdict | `QA PASS: <STORY-ID>` or `QA FAIL-ROUTINE: <STORY-ID>` or `QA FAIL-CRITICAL: <STORY-ID> @supervisor` |
| Merge complete | `MERGED: <STORY-ID>` |
| Pipeline idle | `PIPELINE-IDLE: no unblocked stories — @gurvinder` |
| Exception proposed | `EXCEPTION-PROPOSED: <STORY-ID> — <principle> — <proposed exception>` |

**What "signal only" means:**

❌ Wrong: "I have completed the implementation of the authentication module and all tests are passing. The feature branch is ready for QA review."

✅ Right: `[ENGINEER] DONE: NS-42 — auth module implemented, 23 tests pass`

Gurvinder reads the War Room to get status in 10 seconds. Every extra word costs tokens and buries the signal. If you find yourself writing a sentence, stop and compress it to one line.

## Session End

When your work is done:
1. Ensure all artifacts are committed via git-agent
2. Post completion summary to the war room
3. Terminate cleanly (fresh context is better than stale)
