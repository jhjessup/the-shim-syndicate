# CONSIGLIERE ANALYSIS — The Shim Syndicate Core (Self-Review)

**Subject:** `jhjessup/the-shim-syndicate` — full framework review
**Date:** 2026-06-10
**Analyst:** @consigliere v1.0
**Scope:** All 31 tracked files (~6,100 lines) + uncommitted working-tree state on `main`
**Question:** Improvements, optimizations, anti-patterns, redundancies, inefficiencies.

**FINDING (one line):** The framework's enforcement layer is largely theater — its gates are forgeable or mis-targeted, its flagship v3.4 features are unwired, its registry has drifted from reality, and the working tree on `main` currently contains an uncommitted regression that deletes the resource governor while three identity files still command agents to rely on it.

**SEVERITY:** CRITICAL (3 critical, 5 high, 6 medium, 6 low/hygiene findings)

---

## SECTION 1 — CRITICAL FINDINGS

### C-1. Uncommitted regression on `main` guts the resource governor

**Evidence:**
- `git status`: `M scripts/launch-operative.sh` (−213 / +34 lines), `M identities/THE_LEDGER.md` — uncommitted, sitting directly on `main`.
- The diff deletes: governor pre-flight (`governor_check`), state initialization, cost accumulation (`governor_update`), `--output-format json` cost capture, exit-code-2 HOLD behavior, and all `[GOVERNOR]` logging. It also silently downgrades `gemini-low` from `gemini-2.0-flash-lite` to `gemini-1.5-flash`.
- Meanwhile `THE_LEAD.md §VIII` and `THE_LEDGER.md §VIII` still state: *"All operative launches must go through scripts/launch-operative.sh. Direct `claude --model` calls bypass the resource governor and are prohibited"* and document exit-code-2 hold semantics that no longer exist in the working tree.
- `scripts/update_usage.py` describes itself as *"Thin shim — delegates to the governor state file used by launch-operative.sh"* and instructs *"Run launch-operative.sh once to initialize"* — which the modified script never does. `update_usage.py --status` will exit 1 forever on a fresh machine.
- The companion uncommitted edit to `THE_LEDGER.md` adds Refusal Condition 7 ("No Task Absorption" — Ledger must not absorb a failed operative's work). The juxtaposition strongly suggests an agent session degraded the launcher while working around a failure — exactly the anti-pattern the new rule describes.

**Syndicate diagnosis:** Violates **Principle A (Branch Sovereignty)** — modification of governed infrastructure directly on `main`, no `mission/` branch, no `Syndicate-Audit-Trace`, no AUDIT_LOG entry. Violates **Principle B (Audit & Traceability)** — there is no record of *why* the governor (merged via PR #8, commit `f17da72`) was removed. The core repo does not eat its own dog food: hooks are never installed in the core repo itself, so nothing blocked this.

**Cost:** The governor was v3.4's quota-protection mechanism. Its removal restores unbounded 5-hour-window burn — the precise failure class (quota exhaustion mid-mission) it was built to prevent. Identity files now issue commands (`exit 2` handling, calibration steps) that reference phantom behavior, which will cause agents to mis-handle launcher failures.

**Recommendation:**
1. **Triage now:** either `git checkout -- scripts/launch-operative.sh` (restore governor) or, if removal is a deliberate decision, do it on a `mission/` branch with a logged decision, and update `THE_LEAD.md §VIII`, `THE_LEDGER.md §VIII`, `update_usage.py`, and `manifest.json` in the same change. The half-state is the worst state.
2. Keep the `THE_LEDGER.md` Refusal Condition 7 addition — it is good policy — but land it through the framework's own process (mission branch + audit trace) and bump the Ledger identity version (v3.0 → v3.1) and manifest.
3. Install the Syndicate's own hooks in the core repo (`hooks/pre-commit` → `.git/hooks/`) so the framework governs itself.

### C-2. The audit chain of custody is self-attestable (security theater)

**Evidence:**
- `hooks/commit-msg:50` — the trailer regex `(PASS|CONDITIONAL PASS|FAIL)` accepts a **FAIL** trace, immediately after which the hook's own help text states *"A FAIL trace is never a valid commit state."* A commit carrying `Syndicate-Audit-Trace: @gavel FAIL — …` passes the gate.
- `hooks/pre-commit:325` and `hooks/commit-msg:63` both print a ready-to-paste `@gavel PASS — $(date -u …)` line. `syndicate-init.sh:734-735` goes further: it instructs the operator to commit the freshly created vault with a fabricated `@gavel PASS` trailer **before any Gavel audit has ever run**.
- Nothing verifies that a trailer corresponds to an actual audit report in `AUDIT_LOG.md`. `THE_GAVEL.md §IV` says the AUDIT_TRACE line is "the value The Lead copies" — but any agent or human can mint one.

**Syndicate diagnosis:** Violates **Principle B**: the trailer is the framework's central claim ("immutable chain of custody") and it is trivially forgeable by design. The framework trains its own operators to forge it during onboarding.

**Cost:** Every downstream guarantee (merge gates, deployment gates in ORACLE §6.5, retroactive auditing) inherits zero integrity from the trailer. Compliance claims built on it would not survive scrutiny.

**Recommendation:**
1. Remove `FAIL` from the accepted trailer statuses in `commit-msg`.
2. Bind the trailer to evidence: have Gavel append its report to `AUDIT_LOG.md` ending with a short content hash (e.g., first 12 hex of SHA-256 of the report body); require the trailer format `@gavel PASS — <timestamp> — <hash>`; have `commit-msg` verify the hash appears in the staged/committed `AUDIT_LOG.md`.
3. Delete the "copy this trailer" convenience prints, and fix the `syndicate-init.sh` vault-commit instruction to use a real bootstrap status (e.g., `@gavel BOOTSTRAP`) explicitly permitted only for vault-scaffold commits.

### C-3. The Oracle-integrity gate cannot see most placeholders

**Evidence:**
- `hooks/pre-commit` CHECK-2 and CHECK-5 grep for `\{\{[A-Z_]+\}\}` only.
- `templates/ORACLE.md` placeholders are overwhelmingly lowercase / prose-style: `{{e.g., 90%}}`, `{{description}}`, `{{date}}`, `{{condition}}`, `{{topic and reason}}`, `{{package}}`, `{{operator}}` — none match the regex. `templates/RESERVATIONS.json` uses `{{project_name}}` (lowercase). Only a handful of tokens (`{{OTHER}}`, `{{ADDITIONAL_SOURCE_1}}`, `{{ADDITIONAL_GATE_1}}`…) are detectable.
- Result: an essentially **unfilled Oracle passes CHECK-2 as "fully populated"**, and the Lead's refusal condition ("refuse to operate without a complete Oracle") is keyed to a gate that cannot fire.

**Syndicate diagnosis:** Violates **Principle C (Quality Gates)** — the gate exists but measures the wrong thing. This is the "flaky test masked as fixed" pattern applied to the framework's own tooling.

**Cost:** Agents will operate against skeleton Oracles believing them complete; every downstream audit that cites "Oracle-approved" thresholds is citing `{{e.g., 80%}}`.

**Recommendation:** Pick one and enforce it everywhere: (a) normalize every template token to `{{UPPER_SNAKE}}` (mechanical edit across `templates/`), or (b) broaden the hook regex to `\{\{[^}]+\}\}`. Option (b) is one line in two places and catches everything today; do it first, then normalize templates at leisure. Add the same check to CHECK-2's non-mission path as a FAIL (not WARN) when an agent session is active.

---

## SECTION 2 — HIGH FINDINGS

### H-1. Registry/version drift — the auditability framework cannot audit itself

**Evidence (all verifiable in-tree):**

| Artifact | Claims | Reality |
|----------|--------|---------|
| `manifest.json` `active_version` | 3.4.0 | Commit `4a49554` added a new SDLC phase (PRODUCT DESIGN), Gavel §IX Frontend Hygiene Audit, `templates/UX_AUDIT_PROMPT.md`, ORACLE §4.5–4.7/§6.4 — a textbook MINOR bump with **no manifest entry** |
| `README.md` footer | "Version 3.2.0" | Two minor versions stale |
| `manifest.json` `canonical_branch` | `claude/master-core-setup-PJkxq` | Default branch is `main` |
| `manifest.json` agents.operative | identity_version "1.1" | `THE_OPERATIVE.md` header and footer say **v1.0** (content includes the v1.1 features) |
| `THE_LEAD.md` / `THE_GAVEL.md` versions | v3.1 / v2.0 | Both received substantive new sections (§ PRODUCT DESIGN phase; §IX Frontend Hygiene) since those versions — never bumped |
| `manifest.json` `sops_available` | only `CONTEXT_HYGIENE.md` | `sops/TASK_HYGIENE_SOP.md` exists, unregistered; `scripts/` (launch-operative, session, update_usage) and `shims/pi.shim.json` appear in no registry |
| README "Repository Structure" tree | 5 dirs, ~12 files | Omits `hooks/`, `sops/TASK_HYGIENE_SOP.md`, `THE_CONSIGLIERE.md`, `THE_OPERATIVE.md`, `THE_LEDGER.json`, `pi.shim.json`, 5 of 8 templates, 3 of 4 scripts |
| All three shipped shims | `"syndicate_version": "1.0.0"` | `routing.schema.json` says this field "Must match the version field in manifest.json" (3.4.0) |
| `integrity.sha256_manifest` | "PENDING" in **every** release since 1.0.0 | Tamper-detection field never implemented |

**Syndicate diagnosis:** Principle B violation at the meta level. The product's pitch is "you can always determine which version was active when a decision was made" — currently false even inside the core.

**Cost:** Every hydrated project stamps a `syndicate_version` that doesn't describe what it received. Retroactive auditing — the manifest's stated purpose — is already unreliable at version 3.4.

**Recommendation:** Cut a true-up release (3.5.0) that registers the PRODUCT DESIGN/UX work, bumps identity versions to match content, fixes `canonical_branch`, updates the README footer/tree, and either implements `sha256_manifest` (one `sha256sum` in a release script) or deletes the field. Add a pre-commit check (core-repo-only) that fails when `identities/` or `templates/` change without a manifest delta.

### H-2. THE_LEAD's model binding contradicts every other source

**Evidence:** `THE_LEAD.md:4` — *"Model Binding: Gemini 1.5 Pro / Flash (Optimized for Context & Tool Use)"*. README table, `manifest.json`, and `claude.shim.json` all bind Lead to **Claude Sonnet 4.6**. Gemini 1.5 is also two generations stale relative to the framework's own Gemini 2.5 references.

**Cost:** The identity file is the system prompt. An agent told it *is* Gemini 1.5 while running as Claude Sonnet starts every session with a self-description conflict.

**Recommendation:** One-line fix: `Model Binding: Claude (Sonnet 4.6+)` — matching THE_CONSIGLIERE.md's style.

### H-3. pi.shim.json is unreachable and schema-invalid

**Evidence:**
- `routing.schema.json` declares `additionalProperties: false` at top level and on `agents`; backend enum is `[claude, gemini, local]`; provider enum lacks `openrouter`. `pi.shim.json` declares `"$schema": "./routing.schema.json"` yet uses top-level `cli_tool`, `cli_profile`, `invocation_template`; an `operative` agent key; `primary_backend: "pi"`; provider `openrouter`; fallback `"pi"` — **at least six distinct schema violations** in a file that claims conformance.
- `syndicate-init.sh:155` validates `--shim` against `claude|gemini|local` only. The pi shim cannot be deployed via the official hydration path, despite Lead/Ledger identities offering `pi` as a dispatch tier.
- Local shim (`local.shim.json`) gives Gavel provider `opencode` while the schema enum permits it but `claude.shim.json` gives Gavel `supports_tool_use: false` vs pi shim `true` for the same model — uncurated copy variance.

**Recommendation:** Update `routing.schema.json` (add `pi` backend, `openrouter` provider, optional `operative`/`consigliere` agent keys, `cli_profile`/`invocation_template` definitions), add `pi` to the init script's `--shim` whitelist, and add a 5-line CI/pre-commit step: `for f in shims/*.shim.json; do validate against schema; done`. A schema nobody validates against is decoration.

### H-4. syndicate-session.sh builds agent launch commands and never runs them

**Evidence:**
- `build_agent_commands()` constructs `LEAD_CMD`, `LEDGER_CMD`, `GAVEL_CMD` — **no other line in the script reference them**. The tmux windows (`create_session`) only `echo` identity/oracle paths. The advertised behavior ("auto-loading of mission ORACLE.md and project-map.json into each agent window") does not happen; windows are empty shells with a banner.
- The commands that *are* built use CLI flags that don't exist: `claude --system-file`, `gemini --system-file --context` (the real flags are `--system-prompt`/`--append-system-prompt` for claude, and the README itself uses different gemini flags). `CMD_LEAD` (multi-line variant) is dead code; it also injects only `head -1` of the identity.
- `lead_identity`/`ledger_identity`/`gavel_identity` are declared `local` inside `build_agent_commands` but consumed in `create_session` via `${lead_identity:-…}` — they are always empty at that point; lines 419–421 reset them to empty and the fallback strings mask the bug.

**Cost:** 433 lines maintaining a tmux banner. Operators following the documented flow get four windows and no agents — then hand-assemble launches, bypassing identity injection and (when it existed) the governor.

**Recommendation:** Either (a) finish it — send the (corrected) commands via `tmux send-keys` and verify each CLI's actual flags, or (b) cut it to an honest ~100-line "session scaffold" that opens windows with a printed copy-paste launch line per agent. Delete `CMD_LEAD` dead code either way.

### H-5. The Gavel's launch protocol mandates the exact bypass the other identities prohibit

**Evidence:** `THE_GAVEL.md §XI` instructs direct invocation: `claude --model <model> --print …`. `THE_LEAD.md §VIII` and `THE_LEDGER.md §VIII`: *"Direct `claude --model` calls bypass the resource governor and are prohibited."* All three sections are near-identical ~50-line blocks — duplicated, then independently drifted. This is the root failure mode of copy-paste protocol blocks.

**Cost:** Beyond the contradiction: the tier tables + launch protocol are duplicated across three identity files (~150 lines, ≈1.3–1.5k tokens *per agent per session*, since identities are system prompts). The tier table is additionally duplicated **within** THE_LEAD.md (§III Operative Model Binding vs §VIII Tier Selection).

**Recommendation:** Extract one canonical `sops/OPERATIVE_LAUNCH_PROTOCOL.md` (or a short §reference in each identity: "dispatch per `scripts/launch-operative.sh`; tiers defined in pi.shim/launch script"). Identities should state *policy* ("lowest-cost capable tier; launches go through the wrapper"), not maintain three copies of a model-version table that goes stale on every model release. This is also your single largest recurring token saving.

---

## SECTION 3 — MEDIUM FINDINGS

### M-1. v3.4.0's headline feature (RESERVATIONS) is prose-only

`templates/RESERVATIONS.json` exists (4 lines) and ORACLE §6.3 RULE_1 mandates checking `.syndicate/vault/RESERVATIONS.json` — but `syndicate-init.sh` never stamps or copies it, no script reads/writes/expires locks, and RULE_4's "expire if the PID is no longer running" is unimplementable as a markdown directive. The concurrency-control release shipped a schema and a rule, no mechanism. **Recommendation:** add stamping to init (Step 4.2) and a tiny `scripts/reserve.sh {claim|release|sweep}` helper, or mark §6.3 as ASPIRATIONAL in the template so agents don't cite a registry that doesn't exist.

### M-2. TASK_HYGIENE_SOP references a toolchain that doesn't exist

`sops/TASK_HYGIENE_SOP.md` names `.syndicate/scripts/task-hygiene.py`, `task-hygiene-prompt.md`, `task-graph.yaml`, and "ORACLE Reference: §7.1" — none exist anywhere in the repo (`grep` confirms; ORACLE §7 is the version-history table). Companion drift: `sops/CONTEXT_HYGIENE.md` points to "ORACLE.md §6.4" for `CONTEXT_HYGIENE_THRESHOLD`, but the v3.5-era insertion of §6.4 (Frontend Dependency Workflow) moved the Session Resource Budget to **§6.6**. **Recommendation:** ship the scripts or delete the SOP; fix the § references; stop using positional §-references between files (use anchors/names — "ORACLE: Session Resource Budget").

### M-3. `shims/gavel_audit.py` is broken on first run and orphaned

- Line 24: `os.makedirs(os.path.dirname(STATE_FILE), exist_ok=True)` with `STATE_FILE = "usage_state.json"` → `os.makedirs("")` → `FileNotFoundError`. The script crashes the first time it ever runs.
- `remaining_buffer` is initialized (40000) and **never decremented** anywhere — the "Quota Depleted" gate can never trip; dead logic.
- Magic numbers disagree: `TOKEN_LIMIT = 30000` here vs `token_ceiling: 40000` in `identities/THE_LEDGER.json`.
- Nothing in the repo references `gavel_audit.py`; it lives in `shims/` (a directory the README defines as routing configs).

**Recommendation:** Delete it (the launch-operative governor superseded it), or fix the makedirs guard + wire it into the pre-commit hook as a CHECK-6 if a staged-diff size gate is still wanted.

### M-4. `identities/THE_LEDGER.json` is an orphan from a different naming universe

References "The_Firm", a 40000 token ceiling, "policy_version 2026.04.03". Referenced by zero files. It sits beside the real `THE_LEDGER.md`, inviting accidental ingestion as identity config. **Recommendation:** delete, or rename/move into a `governance/` artifact with a manifest entry if the token ceiling is meant to be real policy.

### M-5. pre-commit hook logic defects

- **CHECK-4 pattern truncation:** `awk '… /^- PATTERN:/{print $3}'` returns only the third whitespace-delimited field — any prohibited pattern containing a space (e.g., `- PATTERN: eval (`) is silently truncated to its first token, changing what gets blocked. Use `sub(/^- PATTERN:[[:space:]]*/, ""); print`.
- **CHECK-4 false "clean" suppression:** the `pass` message is gated on global `FAIL_COUNT -eq 0`, so a CHECK-3 failure suppresses CHECK-4's verdict line (cosmetic but misleading in audit output).
- **Hardcoded count:** `"All $((5)) checks passed"` — magic arithmetic; will silently lie when CHECK-6 is added.
- **Secrets scan breadth:** pattern list misses generic bearer tokens, `sk-` (OpenAI-style), slack `xox*`, and has no entropy heuristic; also a file named `something.envrc` matches the `*.env.*` deny while `secrets.txt` with a raw key passes unless it matches the narrow regexes. Acceptable as a tripwire — document it as such, or delegate CHECK-3 to `gitleaks` when available with the regex list as fallback.

### M-6. syndicate-init.sh robustness and hygiene

- **Fictional CLI flag:** Step 3.1 injects `--read-only-bash` into Gavel's `cli_flags`. No such flag exists for `ollama run`, `opencode`, or `claude` — any executor honoring routing.json will fail to launch Gavel. Either implement read-only enforcement for a real CLI or remove the step.
- **Unescaped sed substitution:** `--operator "Smith & Jones / Acme"` breaks every template stamp (`&` and `/` are sed metacharacters). Escape or switch to `awk`/`envsubst`.
- **Core repo mutation:** Step 7 writes the deployment registry into the *core's* `manifest.json`, leaving the core checkout permanently dirty (the `concierge-hub` entry currently in manifest.json is exactly this). Registry belongs in a gitignored sidecar (`deployments.local.json`) or a dedicated branch — not interleaved with the version registry.
- **No headless mode:** two interactive `read -p` confirmations with no `--yes` flag, in a framework whose identities describe themselves as "headless-first".

---

## SECTION 4 — LOW / HYGIENE FINDINGS

| # | Finding | Location |
|---|---------|----------|
| L-1 | Duplicate section number: two `## X.` headings (Refusal Conditions, Output Standards) | `THE_GAVEL.md:215,226` |
| L-2 | Markdown typos: `**\`project-map.json\`*:**` malformed bold, `** No Hallucinated Progress` stray space — ironic given STYLE_GUIDE.md exists | `THE_LEDGER.md:69-70,105` |
| L-3 | Doubled horizontal rule / orphan `---` pair | `THE_LEAD.md:21-23` |
| L-4 | `THE_LEAD.md` §VI decision-log code fence ends with escaped `\``` ` inside the block — renders broken | `THE_LEAD.md:108` |
| L-5 | `manifest.json` is 463 lines because each version entry re-embeds full agents/shims/compatibility blocks (~80% duplication). Keep `changelog` + deltas only; current-state lives once at top level | `manifest.json` |
| L-6 | `.claude/settings.local.json` allows `Bash(git *)` — a wildcard that subsumes the nine more-specific rules above it and permits `git push --force` to main from any session. Trim to the specific verbs you actually want pre-approved | `.claude/settings.local.json:13` |
| L-7 | `claude.shim.json` ships Lead with `--dangerously-skip-permissions` as the *recommended default* — contradicts "Security by Default" (§II.2 of THE_LEAD). Make it an opt-in documented exception | `claude.shim.json:20` |
| L-8 | `commit-msg` requires a literal em-dash (—) in the trailer; agents emitting ASCII hyphens get blocked with a confusing message. Accept `[—-]` | `hooks/commit-msg:50` |
| L-9 | pi.shim model IDs (`nemotron-3-super-free`, `google/gemini-3.1-flash-lite-preview`, `qwen-2.5-72b`) are unverifiable/likely-stale slugs with no refresh procedure. Add a "verified on <date>" field per model | `shims/pi.shim.json` |

---

## SECTION 5 — ROOT CAUSE ANALYSIS

Three systemic causes explain ~90% of the findings:

1. **No self-application.** The core repo does not run its own hooks, has no CI, and accepts direct-to-`main` work (C-1 is live proof). A governance framework that exempts itself accumulates exactly the violations it sells protection against.
2. **Duplication as distribution.** Protocol text is copy-pasted across identities (H-5), version data across manifest entries (L-5), tier tables within files. Every copy is a future contradiction; several have already diverged.
3. **Spec-first releases without mechanism.** v3.4 (RESERVATIONS), TASK_HYGIENE_SOP, the schema, and session manager all shipped documentation of behavior that no code performs (M-1, M-2, H-3, H-4). The framework's prose has outrun its tooling, and the gates that *do* exist (C-2, C-3) don't verify what they claim.

---

## SECTION 6 — QUANTIFIED IMPACT

- **Token burn (recurring):** ~1.3–1.5k tokens of duplicated launch-protocol text injected per agent per session × 3 agents ≈ 4–4.5k tokens/session of pure duplication, before any work happens. Across a 20-session mission: ~80–90k tokens of waste.
- **Quota risk (latent):** governor removal (C-1) reverts to pre-v3.4 unbounded window burn; the v3.4 work (commit `f17da72`, PR #8 — an entire feature cycle) is currently nullified by an unreviewed working-tree edit.
- **Rework multiplier:** 6 documented features reference nonexistent mechanisms (RESERVATIONS protocol, task-hygiene toolchain, `--read-only-bash`, session auto-launch, sha256 integrity, schema validation). Each will resurface as a confused agent session or failed hydration before it resurfaces as a backlog item.
- **Trust exposure:** the two integrity primitives the framework advertises — placeholder gating and audit traces — are respectively blind (C-3) and forgeable (C-2). Time broken code could sit "audited" on a mission branch: unbounded.

---

## SECTION 7 — RECOMMENDATIONS (PHASED)

### Phase 0 — Today (triage, < 1 hour)
1. Resolve the uncommitted `main` diff (C-1): restore the governor or land its removal properly. Do not leave it ambient.
2. Broaden hook placeholder regex to `\{\{[^}]+\}\}` (C-3) and remove `FAIL` from the commit-msg trailer regex (C-2 partial).
3. Fix `THE_LEAD.md` model binding line (H-2).
4. Install the Syndicate hooks into the core repo's own `.git/hooks/`.

### Phase 1 — This week (true-up release v3.5.0)
5. Manifest true-up: register the PRODUCT DESIGN/UX changes, bump identity versions (Lead → 3.2, Gavel → 2.1, Ledger → 3.1, Operative header → 1.1), fix `canonical_branch`, README footer + structure tree, shim `syndicate_version` policy (H-1).
6. De-duplicate the Operative Launch Protocol into one canonical document; identities keep a 3-line policy reference (H-5). Collapse manifest version entries to changelog-only (L-5).
7. Decide the fate of orphans: `gavel_audit.py`, `THE_LEDGER.json` (M-3, M-4) — recommend deletion.

### Phase 2 — Next mission cycle (mechanism debt)
8. Schema v2 + shim validation in pre-commit; add `pi` to init's `--shim` whitelist (H-3).
9. Wire RESERVATIONS into init + a `reserve.sh` helper, or downgrade ORACLE §6.3 to aspirational (M-1).
10. Ship or delete the task-hygiene toolchain; replace positional §-references with named anchors (M-2).
11. Rebuild or honestly downscope `syndicate-session.sh` (H-4); fix init's sed-escaping, registry side-effect, `--read-only-bash`, and add `--yes` (M-6).
12. Implement evidence-bound audit traces (hash-linked to AUDIT_LOG entries) — this converts the framework's central claim from theater to mechanism (C-2 full fix).

---

## SECTION 8 — WHAT IS WORKING (for balance)

- `hooks/pre-commit` structure (5 ordered checks, clear PASS/FAIL/WARN output, hard exit semantics) is genuinely good operator UX — the defects are in pattern coverage, not architecture.
- The identity separation (orchestrators vs. enforcement/execution), the dispatch-package contract in `THE_OPERATIVE.md`, and the Deferred Finding Protocol in `THE_GAVEL.md` are coherent, well-specified designs.
- `templates/ORACLE.md` and `TEST_DOCTRINE` two-tier design (universal core + project instantiation) is the right shape; the Frontend Hygiene Audit (Gavel §IX) encodes real, specific failure patterns (lock-file atomicity, selector discipline, PHI leak paths) with evidence commands — the strongest recent addition.
- The uncommitted "No Task Absorption" Ledger rule is exactly the right lesson extracted from whatever incident produced C-1. Land it properly.

---

*Filed by @consigliere — pattern recognition across time and portfolio.*
*Sources: full read of all 31 tracked files, `git log`/`git status`/`git diff` of working tree, cross-reference greps for orphan and dangling references. No external assumptions.*

---

## ADDENDUM — PHASE 0 EXECUTION RECORD

**Executed:** 2026-06-10, by two parallel operatives under @consigliere direction (disjoint file scopes — no reservation collision).

| Phase 0 Item | Finding | Action Taken | Verification |
|---|---|---|---|
| 1. Resolve uncommitted `main` diff | C-1 | `git checkout -- scripts/launch-operative.sh` — governor restored (governor_init/check/update present, `gemini-2.0-flash-lite` reinstated). The good `THE_LEDGER.md` "No Task Absorption" edit preserved untouched. | `bash -n` PASS; `git diff --stat` shows launcher clean |
| 2a. Broaden placeholder regex | C-3 | `hooks/pre-commit`: `\{\{[A-Z_]+\}\}` → `\{\{[^}]+\}\}` at all 3 sites (CHECK-2 ×2, CHECK-5) | `bash -n` PASS; 3 occurrences confirmed, 0 of old pattern |
| 2b. Remove FAIL from trailer | C-2 (partial) | `hooks/commit-msg` TRAILER_PATTERN: `(PASS\|CONDITIONAL PASS\|FAIL)` → `(PASS\|CONDITIONAL PASS)` | `bash -n` PASS |
| 3. Fix Lead model binding | H-2 | `identities/THE_LEAD.md:4` → `**Model Binding:** Claude (Sonnet 4.6+)` | Matches README/manifest/claude.shim |
| 4. Self-application of hooks | Root cause 1 | Fixed hooks installed to `.git/hooks/` (pre-commit, commit-msg), executable, byte-identical to source | `cmp` PASS; `ls -l` confirms `-rwxr-xr-x` |

**Working tree after Phase 0:** modified — `hooks/commit-msg`, `hooks/pre-commit`, `identities/THE_LEAD.md`, `identities/THE_LEDGER.md`; untracked — this review file.

**Consequence (intentional):** the core repo now enforces its own Branch Sovereignty. These pending changes **cannot be committed on `main`** — land them via `git checkout -b mission/phase-0-remediation` with a `Syndicate-Audit-Trace` trailer (`@gavel FAIL` is no longer accepted).

**Known tradeoff accepted:** the broadened regex will also flag prose `{{placeholder}}` mentions inside hydrated ORACLE/TEST_DOCTRINE files. This is the safe direction (false block > false pass); template prose should avoid literal double-brace tokens (Phase 1, item 6 territory).

**Remaining open:** C-2 full fix (hash-bound trailers), all Phase 1 and Phase 2 items.

---

## ADDENDUM — PHASE 1 EXECUTION RECORD

**Executed:** 2026-06-10, on `mission/consigliere-remediation` (Phase 0 landed as `74a3ae1` — the first commit in this repo's history gated by its own hooks). Two parallel operatives with disjoint file scopes, plus one inline hook fix by @consigliere.

| Phase 1 Item | Finding | Action Taken | Verification |
|---|---|---|---|
| 5. Manifest true-up → v3.5.0 | H-1 | New 3.5.0 entry registering the unversioned 4a49554 changes + this remediation; `canonical_branch` → `main`; superseded entries collapsed to changelog-only (464 → 231 lines); unimplementable `sha256_manifest` field removed; pi shim, TASK_HYGIENE_SOP, UX_AUDIT_PROMPT, RESERVATIONS, and a scripts registry all registered | `jq` VALID; active_version 3.5.0; 7 version entries |
| 5. README sync | H-1 | Footer 3.2.0 → 3.5.0; Consigliere added to team table; structure tree corrected to actual repo contents (was missing hooks/, 2 SOPs, 5 templates, 3 scripts, 2 identities, pi shim) | zero residual "3.2.0" |
| 5. Identity version bumps | H-1 | Lead 3.1→3.2, Ledger 3.0→3.1, Gavel 2.0→2.1, Operative header 1.0→1.1 — matching manifest | headers + footers consistent |
| 5. Shim version policy | H-1 | `syndicate_version` redefined in schema as "authored against core version"; all four shims stamped 3.5.0 | `jq` OK ×5 |
| 6. Launch protocol consolidation | H-5 | New canonical `sops/OPERATIVE_LAUNCH_PROTOCOL.md` v1.0; triplicated blocks replaced with compact policy references (Lead −58 lines, Ledger −63, Gavel −39); **Gavel's direct-invocation contradiction resolved** — all launches now route through `launch-operative.sh` | tier-to-model table exists in exactly one file |
| 6. Markdown hygiene (opportunistic, same files) | L-1..L-4 | Gavel duplicate §X renumbered (X/XI/XII); Lead doubled `---` and broken §VI fence fixed; Ledger stray-asterisk and bold-spacing typos fixed | grep confirms unique section numbers |
| 7. Orphan removal | M-3, M-4 | `git rm shims/gavel_audit.py` (crashed on first run, dead quota logic) and `identities/THE_LEDGER.json` (referenced by nothing) | staged deletions |
| NEW: F-1 (found by dogfooding) | — | During the Phase 0 commit, the live hook run revealed CHECK-3 patterns beginning with `-` (the private-key header) were parsed by grep as **options** and silently skipped — private-key detection had never functioned. Fixed with `grep -qiE -e "$pattern"`; hook reinstalled | a sample RSA private-key header (defanged here — the working gate now flags the literal, which it proved by blocking the first draft of this very row) now matches |

**Token-burn payoff (H-5):** ~160 lines of duplicated protocol removed from identity system prompts ≈ 4–4.5k tokens saved per 3-agent session, recurring.

**Remaining open:** C-2 full fix (hash-bound audit trailers) and all Phase 2 items — schema v2 + shim validation, RESERVATIONS mechanism, task-hygiene toolchain decision, session manager rebuild/downscope, init-script robustness (`--read-only-bash`, sed escaping, registry side-effect, `--yes`).
