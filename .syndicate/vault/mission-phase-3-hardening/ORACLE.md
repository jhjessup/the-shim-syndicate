# ORACLE — Mission Configuration
**Project:** `the-shim-syndicate — mission/phase-3-hardening`
**Hydrated From:** The Shim Syndicate `v3.6.0` (core repo self-application)
**Mission Date:** `2026-06-11`
**Operator:** `Jonathan Jessup`

---

> **Mission Oracle.** Branch-local ground truth for `mission/phase-3-hardening`. This mission closes the residual LOW/MEDIUM findings parked as Phase 3 candidates in `CONSIGLIERE_REVIEW_2026-06-10.md` (final addendum).

---

## 1. Mission Context

```
DOMAIN: Developer Tooling / AI Agent Governance Framework
PURPOSE: Phase 3 hardening — secrets-scan breadth + gitleaks delegation (M-5), CHECK-4 multi-word patterns (M-5), opt-in strict trace-hash mode (C-2 migration path), pi.shim model verification annotations (L-9), permission posture fixes (L-6, L-7).
STAGE: Maintenance — residual finding closure
```

## 2. Constraints

- CONSTRAINT_1: Scope is limited to the Phase 3 candidates named in the review's Phase 2 addendum. Identity files in `identities/` are NOT modified.
- CONSTRAINT_2: All shims must continue to pass `scripts/validate-shims.sh` after editing (CHECK-6 enforces this at commit time).
- CONSTRAINT_3: Hook changes must be backward-compatible by default — stricter behavior is opt-in via environment variable, not imposed (hydrated projects must not break).
- CONSTRAINT_4: gitleaks integration must degrade gracefully — the regex fallback remains fully functional when gitleaks is not installed.
- CONSTRAINT_5: All markdown edits must comply with `STYLE_GUIDE.md`.

## 3. Scope

In scope: `hooks/pre-commit`, `hooks/commit-msg`, `shims/pi.shim.json`, `shims/claude.shim.json`, `.claude/settings.local.json`, `manifest.json` (v3.7.0), `README.md` (footer), `CONSIGLIERE_REVIEW_2026-06-10.md` (addendum).

Out of scope: everything else, notably `identities/`, `scripts/`, `templates/`, `sops/`.

## 4. Audit Record

`CONSIGLIERE_REVIEW_2026-06-10.md` (Phase 3 addendum) plus the vault `logs/AUDIT_LOG.md` back the evidence-bound `Syndicate-Audit-Trace` trailers on this branch.

---

*Mission-local Oracle. Successor mission to `mission/phase-2-mechanisms` (PR #10).*
