# ORACLE — Mission Configuration
**Project:** `the-shim-syndicate — mission/phase-2-mechanisms`
**Hydrated From:** The Shim Syndicate `v3.5.0` (manual mission scaffold — core repo self-application)
**Mission Date:** `2026-06-10`
**Operator:** `Jonathan Jessup`

---

> **Mission Oracle.** Branch-local ground truth for `mission/phase-2-mechanisms`. This mission converts the framework's documented-but-unimplemented behaviors into working mechanisms (CONSIGLIERE_REVIEW_2026-06-10.md, Phase 2).

---

## 1. Mission Context

```
DOMAIN: Developer Tooling / AI Agent Governance Framework
PURPOSE: Implement Phase 2 of the Consigliere remediation — schema v2 + shim validation, RESERVATIONS mechanism, evidence-bound audit traces, session manager downscope, init-script robustness, task-hygiene SOP true-up.
STAGE: Maintenance — mechanism debt payoff
```

## 2. Constraints

- CONSTRAINT_1: Scope is limited to Phase 2 items as defined in `CONSIGLIERE_REVIEW_2026-06-10.md` §7 (items 8–12). Identity files in `identities/` are NOT modified in this mission (no version churn two missions in a row); identity-facing documentation changes go to `sops/` or hook comments.
- CONSTRAINT_2: All schema changes must remain backward-compatible — every existing shim must still validate.
- CONSTRAINT_3: New scripts must pass `bash -n` (shell) or `python3 -m py_compile` (python), be executable, and depend only on the framework's required tooling (git, jq, bash, python3 stdlib).
- CONSTRAINT_4: The evidence-bound trailer verification must be transitional: hash verified when present, warning (not failure) when absent, so existing hydrated projects do not break.
- CONSTRAINT_5: All markdown edits must comply with `STYLE_GUIDE.md`.

## 3. Scope

In scope: `shims/routing.schema.json`, `scripts/` (syndicate-init.sh, syndicate-session.sh, new validate-shims.sh, new reserve.sh, new audit-trace.sh), `hooks/` (pre-commit CHECK-6, commit-msg hash verification), `templates/ORACLE.md` §6.3, `sops/TASK_HYGIENE_SOP.md`, `sops/CONTEXT_HYGIENE.md`, `manifest.json` (v3.6.0), `README.md`, `.gitignore`, `CONSIGLIERE_REVIEW_2026-06-10.md` (addendum).

Out of scope: `identities/`, `templates/` other than ORACLE.md §6.3, the pi.shim model ID refresh (L-9), settings files.

## 4. Audit Record

`CONSIGLIERE_REVIEW_2026-06-10.md` (Phase 2 addendum) serves as the written audit record backing the `Syndicate-Audit-Trace` trailers on this branch.

---

*Mission-local Oracle. Successor mission to `mission/consigliere-remediation` (PR #9).*
