# SOP — Context Hygiene & Session Lifecycle Management
**Document Type:** Operator Standard Operating Procedure  
**Syndicate Handle:** N/A (Operator-executed, not agent-executed)  
**Version:** 1.0  
**Applies To:** All Syndicate sessions running on Claude Code CLI

---

> **What this SOP is:**  
> A set of operator-executed procedures for managing session health, context load, and continuity across the 5-minute prompt cache boundary. These procedures use Claude Code CLI slash commands and are not embedded in agent identity files (which must remain model-agnostic).

---

## When to Execute This SOP

Execute this procedure at **any** of the following triggers:

- Context load reaches the threshold defined in `ORACLE.md §6.4` (`CONTEXT_HYGIENE_THRESHOLD`, default: 60%)
- Before beginning a major refactor or phase transition
- Before handing off to a different agent (e.g., switching from @lead session to @gavel audit)
- If you are stepping away from the terminal for more than 5 minutes (cache boundary)
- If agent responses begin showing signs of context drift (referencing stale decisions, re-asking answered questions)

---

## Procedure: Syndicate Snapshot & Compact

Execute the following steps in sequence. Do not skip steps.

### Step 1 — Log Resource State
```
/context
/cost
```
Record the output. Note the current context percentage and cumulative cost. Log to `AUDIT_LOG.md`:

```markdown
[DATE] [OPERATOR] CONTEXT_HYGIENE: Context at XX%, cost $X.XX — snapshot initiated.
```

### Step 2 — Capture the Architectural Kernel

Before compacting, explicitly ask the active agent:

```
Summarize for a fresh session:
1. The current mission branch and active ORACLE.md path
2. All architectural decisions made in this session (with their rationale)
3. The current state of the task queue (task IDs, statuses)
4. The next 3 moves in priority order
5. Any unresolved findings or open questions

Format this as a "Session Handoff Block" — dense, no filler.
```

Copy the agent's output to your clipboard. This is your **Session Carry**.

### Step 3 — Compact
```
/compact
```

### Step 4 — Verify Lore Integrity

After compacting, issue a test prompt:

```
Confirm: What is the active mission branch, and what are the first 2 open tasks in the queue?
```

If the agent's answer deviates from the Session Carry captured in Step 2, the compact was lossy. Re-initialize:

```
System: [re-paste full identity file content]
Session Carry: [paste the Session Handoff Block from Step 2]
```

---

## Procedure: Cache Boundary Recovery (5-Minute Rule)

The Anthropic prompt cache expires after **300 seconds of inactivity**. A stale cache means the next prompt re-processes the full context from scratch at full token cost.

**If stepping away for > 5 minutes:**

1. Before leaving — execute the Syndicate Snapshot & Compact procedure above
2. Copy the Session Carry to clipboard
3. Run `/clear` to reset the session cleanly (cheaper than paying for full stale re-process)
4. On return — start a new session and paste the Session Carry as the first message

**If you forgot and the cache already expired:**

Do not continue in the bloated session. Run `/cost` to confirm re-processing occurred, then:
1. `/clear`
2. Re-initialize from Session Carry

---

## What Belongs in a Session Handoff Block

A well-formed Session Carry block contains:

```
SYNDICATE SESSION CARRY
Branch: mission/[name]
Oracle: .syndicate/vault/[branch]/ORACLE.md
Session Date: [ISO-8601]

DECISIONS:
- [short title]: [one-line rationale] — confirmed by @lead on [timestamp]

TASK QUEUE STATE:
- TASK-001: [status] — [one-line summary]
- TASK-002: [status] — [one-line summary]

OPEN FINDINGS:
- [GAVEL finding ID or description, if any]

NEXT MOVES:
1. [highest priority action]
2. [second]
3. [third]

CONTEXT CARRY HASH: [first 8 chars of git HEAD SHA, for integrity verification]
```

---

## Anti-Patterns to Avoid

| Anti-Pattern | Why It Fails |
|---|---|
| Skipping `/cost` before compacting | You lose the baseline. Trend data becomes meaningless. |
| Compacting without capturing the Session Carry | Compact is lossy by design. You cannot recover what you didn't save. |
| Continuing after cache expiry without clearing | You pay re-processing cost AND carry a bloated history. Double waste. |
| Asking the agent to "remember" the compact output | The agent cannot hold state across `/clear`. The Session Carry is your persistence layer. |
| Embedding `/compact` logic in agent identity files | These commands are CLI-specific. Identity files run on Gemini and local models that have no `/compact` command. |

---

*This SOP is version-controlled in `sops/CONTEXT_HYGIENE.md`. It is part of the Syndicate Core and is deployed alongside identity files. It does not require project-local overrides — it applies universally to all Claude Code CLI sessions.*
