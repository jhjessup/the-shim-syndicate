# SOP — Task Queue Hygiene
**Document Type:** Operator Standard Operating Procedure  
**Syndicate Handle:** @ledger (owns execution)  
**Version:** 1.0  
**Introduced:** 2026-04-13  
**Companion Script:** `.syndicate/scripts/task-hygiene.py`  
**Companion Prompt:** `.syndicate/scripts/task-hygiene-prompt.md`  
**ORACLE Reference:** §7.1

---

> **What this SOP is:**
> A daily procedure to keep the three Syndicate sources of truth — `task-graph.yaml`,
> `project-map.json`, and `tasks/dispatch/` packages — synchronized. Task statuses
> drift across sessions because agents update dispatch packages without advancing the
> registry files. This SOP automates detection and correction of that drift.

---

## When to Execute

Run task hygiene at **any** of the following triggers:

| Trigger | Notes |
|---------|-------|
| **Daily** (session start) | Default cadence — prevents drift accumulation |
| **After any operative completes a task** | Operative may have updated dispatch but not registries |
| **Before dispatching new tasks** | Ensures READY/BLOCKED state is accurate |
| **After a branch merge to main** | Merges can leave statuses from the feature branch |
| **After @gavel audit** | Audits add new tasks; initial status is BACKLOG — run hygiene to advance |
| **When another session reports "inconsistent status"** | The canonical fix |

---

## Procedure

### Option A — Script (preferred)

```bash
# From repo root
python3 .syndicate/scripts/task-hygiene.py
```

Review the output. If corrections were applied, the script writes them and appends
to `AUDIT_LOG.md` automatically. No further action needed.

```bash
# Safe preview before committing
python3 .syndicate/scripts/task-hygiene.py --dry-run

# Focus on the active phase only (faster, less noise)
python3 .syndicate/scripts/task-hygiene.py --scope AUDIT
```

### Option B — Haiku Agent (when script is unavailable)

```python
# In a Claude Code session
Agent(
    description="Daily task hygiene check",
    subagent_type="general-purpose",
    model="haiku",
    prompt=open(".syndicate/scripts/task-hygiene-prompt.md").read()
)
```

### Option C — Via @ledger (in-session)

Ask @ledger directly:
```
Run task hygiene. Reconcile task-graph.yaml against project-map.json 
and all dispatch packages, then correct any drift.
```

@ledger will invoke the script or haiku prompt per `routing.json` rule
`task-hygiene-to-ledger`.

---

## What the Script Checks

1. **Status reconciliation** — Compares `task-graph.yaml` status vs `project-map.json`
   status for every task. Applies the state machine:
   - `BACKLOG → READY` when all `depends_on` are `COMPLETE` and a dispatch package exists
   - `BACKLOG/READY → BLOCKED` when any `depends_on` is not `COMPLETE`
   - `COMPLETE` / `FAILED` are never regressed

2. **Source agreement** — Flags tasks where `task-graph.yaml` and `project-map.json`
   disagree (e.g., one says `READY`, other says `BACKLOG`)

3. **Stale reservation locks** — Reports any `active_locks` in `RESERVATIONS.json`
   that may have been left by a crashed or timed-out operative

4. **Dispatch package coverage** — Flags tasks in `BACKLOG`/`BLOCKED`/`READY` with
   no dispatch package (needs @ledger attention before task can advance)

---

## Interpreting the Output

| Icon | Meaning |
|------|---------|
| ✅ COMPLETE | Terminal — no action |
| 🟢 READY | Dispatch package exists, deps clear — safe to dispatch |
| 🔴 BLOCKED | Waiting on a dependency — do not dispatch |
| ⬜ BACKLOG | No dispatch package yet — @ledger must create one |
| 🔄 IN_PROGRESS | Operative is active — do not re-dispatch |
| ⚠ | Discrepancy or attention required |

---

## Known Limitation — YAML Defect

`tasks/task-graph.yaml` has a pre-existing structural defect: Phase 8 tasks (AUDIT-*)
use column-0 indentation while Phases 2–7 use 2-space indentation, and there is no
root key. The file is not parseable by `yaml.safe_load`. The hygiene script uses
regex parsing to work around this. Do not attempt to fix this with `yaml.safe_load`
— the file must be manually restructured first (tracked as a backlog cleanup item).

---

## After Running

If corrections were applied:
- Both `tasks/task-graph.yaml` and `.syndicate/vault/main/project-map.json` are updated
- `AUDIT_LOG.md` has a new `HYGIENE-RUN` entry
- No commit is required unless you want to checkpoint the state — hygiene files are
  Syndicate internal bookkeeping and do not need to be in every commit

If the queue shows `⚠` items the script cannot auto-fix (e.g., missing dispatch
packages, stale locks), escalate to @ledger for manual triage.
