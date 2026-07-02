# SYNDICATE GOVERNANCE — How the Core Itself Is Governed

**Applies to:** `the-shim-syndicate` (the framework core) — this repository.
**Status:** Meta-charter. Supersedes any assumption that the core is governed by
the mission apparatus it ships.

---

## 0. Why this document exists

The Shim Syndicate is a framework for governing **missions that produce
software** — artifacts with a runtime, users, data, a deployment, and a
definition-of-done tied to behavior. This repository is **not** such a mission.
It is the **constitution and toolchain**: doctrine (identities, SOPs),
enforcement (git hooks), and scaffolding (templates, `syndicate-init.sh`).

A constitution is not governed by the ordinary laws it creates — it is governed
by an **amendment process**. Applying the full mission apparatus to the core is
a category error (the equivalent of running unit-coverage gates on a book of
law). This charter defines the amendment process the core *is* governed by, and
records what deliberately does **not** apply.

---

## 1. What governs the core (the amendment process)

Every change to the core follows this lightweight process:

1. **Branch + PR.** No direct commits to `main`/`master`. Work lands on a
   `feat/<topic>` branch (or `fix/<topic>`) and merges via pull request. This is
   universal engineering hygiene, not the mission apparatus — the core already
   works this way.
2. **Downstream dogfood is the acceptance test.** The core has no meaningful unit
   coverage; its correctness is *whether a change actually improves real
   missions*. A doctrine/tooling change must be exercised against at least one
   real downstream project before merge, and the result noted in the PR. This is
   the core's equivalent of a test suite, and it is a **Consigliere** (portfolio /
   downstream-impact) judgment, not a Gavel-vs-ORACLE audit.
3. **SemVer on the framework.** User-visible doctrine or interface changes bump
   `manifest.json` per semantic versioning. Breaking downstream contracts is a
   MAJOR bump and must say so in the PR.
4. **Decision record.** The *why* of a doctrine change lives in the PR
   description and, where consequential, `CHANGELOG`/release notes. The core does
   not maintain a per-mission `AUDIT_LOG.md`.
5. **Dogfood the hooks.** Work on the core through its own `pre-commit` /
   `commit-msg` hooks. Breaking your own tooling is discovered by using it. This
   is a feature, subject to the escape hatch in §3.

---

## 2. What deliberately does NOT apply to the core

The following mission mechanisms are intentionally **out of scope** for this
repository. Do not add them here; their presence would be cargo-cult ceremony:

| Mission mechanism | Why it does not apply to the core |
|-------------------|-----------------------------------|
| Mission vaults (`.syndicate/vault/mission-*`) | The core is not a mission of any project; it *is* the syndicate. |
| `project-map.json` | A living map of modules/APIs/debt suits a codebase you build features in; the core is a stable ruleset. |
| ORACLE coverage thresholds (90/80/60) | Meaningless for bash + markdown. |
| The Lead/Ledger/Gavel triad as a project team | "Gavel audits against ORACLE" is circular here — the core is what *defines* ORACLE. |
| Deployment gate | Nothing deploys. |
| Per-commit `Syndicate-Audit-Trace: @gavel` requirement | The trailer attests a mission audit; the core's review is a Consigliere downstream-impact review, recorded in the PR. |

If a future need looks like it wants one of these, that is a signal the work
belongs in a **downstream project**, not in the core.

---

## 3. The bootstrap escape hatch (mandatory)

Because the core enforces the very hooks it ships, a bug in a hook can lock the
repository — you could be unable to commit the fix to the hook that is blocking
you. Therefore:

- A commit that **repairs the enforcement tooling itself** may bypass the hooks
  with `git commit --no-verify`, provided the PR description states *which* guard
  was bypassed and *why*.
- Hooks that could plausibly self-brick SHOULD detect that they are running
  inside the core repository and degrade to warn-only for the specific checks
  that would otherwise prevent their own repair.
- No such escape hatch exists (or is needed) for downstream missions — this
  clause is unique to the core.

---

## 4. Roles for core changes

- **Consigliere** — primary reviewer of core changes: does this amendment improve
  or harm downstream missions? Is it internally consistent? Reversible? This is
  the core's review authority, in place of a project Gavel.
- **Operator** — ratifies via PR approval and the SemVer decision.
- Lead/Ledger/Gavel identities are **authored and maintained** here, but they do
  not convene *as a mission team* to govern the core.

---

## 5. Amendment checklist

Before merging a change to the core:

- [ ] On a `feat/`/`fix/` branch, not `main` — merging via PR.
- [ ] Change dogfooded against at least one real downstream project; result noted
      in the PR.
- [ ] SemVer impact assessed (`manifest.json` bumped if user-visible; MAJOR if a
      downstream contract breaks).
- [ ] PR description records the rationale (the amendment's "why").
- [ ] If enforcement tooling was bypassed to land the fix, the `--no-verify`
      reason is stated in the PR.
- [ ] No mission apparatus (§2) was introduced into this repository.

---

*This charter is versioned with the core. Amendments to the amendment process
follow the amendment process.*
