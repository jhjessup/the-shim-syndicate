# SOP — Task Queue Hygiene
**Document Type:** Operator Standard Operating Procedure  
**Syndicate Handle:** `@ledger` (owns execution)  
**Version:** 1.1  
**Introduced:** 2026-04-13  
**ORACLE Reference:** `ORACLE.md` — Agent Safety & Concurrency Rules section  
**Status:** Manual procedure (companion automation not yet shipped — see `CONSIGLIERE_REVIEW_2026-06-10.md` M-2)

---

> **What this SOP is:**
> A daily procedure to keep the two Syndicate sources of truth — `project-map.json`
> (the `task_queue` array and its embedded dispatch packages) and `AUDIT_LOG.md` —
> synchronized. Task statuses drift across sessions because agents update dispatch
> package state without advancing the queue entry. This SOP detects and corrects
> that drift.

---

## When to Execute

Run task hygiene at **any** of the following triggers:

| Trigger | Notes |
|---------|-------|
| **Daily** (session start) | Default cadence — prevents drift accumulation |
| **After any operative completes a task** | Operative may have updated its dispatch package without advancing the queue entry |
| **Before dispatching new tasks** | Ensures `READY`/`BACKLOG` state is accurate |
| **After a branch merge to main** | Merges can leave statuses from the feature branch |
| **After `@gavel` audit** | Audits add new tasks; initial status is `BACKLOG` — run hygiene to advance |
| **When another session reports "inconsistent status"** | The canonical fix |

---

## Procedure

Executed manually by `@ledger` (or the operator acting as `@ledger`):

1. **Walk the queue.** Read every entry in the `task_queue` array of `project-map.json`. Valid states are `BACKLOG`, `READY`, `IN_PROGRESS`, `VALIDATING`, `FAILED`, and `COMPLETED` (per `THE_LEDGER.md` §IV).
2. **Cross-check dispatch packages.** For each task, compare the queue status against the state recorded in its embedded dispatch package. A package marked done while the queue says `IN_PROGRESS` is drift.
3. **Cross-check the audit trail.** Compare each task against recent `AUDIT_LOG.md` entries. A logged completion, failure, or audit verdict the queue does not reflect is drift.
4. **Correct the drift.** Update the `task_queue` entry to the evidenced state, applying the state machine:
   - `BACKLOG → READY` only when all dependencies are `COMPLETED` and a dispatch package exists
   - `COMPLETED` and `FAILED` are terminal — never regress them
   - Tasks in `BACKLOG` with no dispatch package need `@ledger` attention before they can advance
5. **Record the correction.** Append a one-line record to `AUDIT_LOG.md`:

```text
[DATE] @ledger HYGIENE: [TASK-ID] corrected [old status] → [new status] — [one-line evidence]
```

If a task cannot be reconciled from the available evidence (conflicting dispatch and audit records, or an operative that may still be active), do not guess — escalate to the operator for manual triage.

---

## Future Automation

The companion task-hygiene script referenced by earlier versions of this SOP was never shipped; this procedure is manual until it exists. The automation gap is tracked as finding M-2 in `CONSIGLIERE_REVIEW_2026-06-10.md`.

---

*This SOP lives in `sops/TASK_HYGIENE_SOP.md`. It is part of the Syndicate Core and applies to every project with a hydrated `project-map.json`.*
