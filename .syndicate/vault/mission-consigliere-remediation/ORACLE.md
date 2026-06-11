# ORACLE — Mission Configuration
**Project:** `the-shim-syndicate — mission/consigliere-remediation`
**Hydrated From:** The Shim Syndicate `v3.4.0` (manual mission scaffold — core repo self-application)
**Mission Date:** `2026-06-10`
**Operator:** `Jonathan Jessup`

---

> **Mission Oracle.** This is the branch-local ground truth for `mission/consigliere-remediation`. The Syndicate core repo now governs itself with its own hooks; this vault satisfies the Mission Architecture requirements for that governance.

---

## 1. Mission Context

```
DOMAIN: Developer Tooling / AI Agent Governance Framework
PURPOSE: Remediate findings from CONSIGLIERE_REVIEW_2026-06-10.md — Phase 0 (gate hardening, governor restore, binding fix) and Phase 1 (v3.5.0 governance true-up, launch protocol consolidation, orphan removal).
STAGE: Maintenance — governance true-up
```

## 2. Constraints

- CONSTRAINT_1: Scope is limited to Phase 0 and Phase 1 items as defined in `CONSIGLIERE_REVIEW_2026-06-10.md` §7. Phase 2 items (schema v2, RESERVATIONS wiring, session manager rebuild, hash-bound traces) are out of scope for this mission.
- CONSTRAINT_2: No behavioral changes to `scripts/syndicate-init.sh` or `scripts/syndicate-session.sh` in this mission.
- CONSTRAINT_3: All markdown edits must comply with `STYLE_GUIDE.md`.
- CONSTRAINT_4: Identity files changed in this mission must receive a version bump recorded in `manifest.json`.

## 3. Scope

In scope: `hooks/`, `identities/`, `sops/`, `manifest.json`, `README.md`, `shims/` (version fields and schema description only), deletion of orphaned files, `CONSIGLIERE_REVIEW_2026-06-10.md`.

Out of scope: everything else.

## 4. Audit Record

`CONSIGLIERE_REVIEW_2026-06-10.md` (finding → action → verification chain) serves as the written audit record backing the `Syndicate-Audit-Trace` trailers on this branch.

---

*Mission-local Oracle. Created manually because the core repo is not a hydrated project; this is intentional self-application of the Mission Architecture.*
