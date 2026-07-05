#!/usr/bin/env bash
# =============================================================================
# branch-hygiene.sh — Pi operative for CI status, merge-conflict, and rebase
# =============================================================================
# USAGE:
#   branch-hygiene.sh <PR_NUMBER> [CI_FACTS_FILE]
#
# ARGUMENTS:
#   PR_NUMBER      GitHub PR number to investigate (required)
#   CI_FACTS_FILE  Path to a project-local ci-facts.md (optional; omit if the
#                  project has no local CI chain to run)
#
# EXAMPLES:
#   branch-hygiene.sh 249
#   branch-hygiene.sh 249 /root/concierge-hub/docs/ops/ci-facts.md
#
# WHAT IT DOES:
#   1. Checks CI status on the PR
#   2. If CI never fired: diagnoses why (stale commits, non-mergeable) and fixes
#   3. If CI failed: runs the full local CI chain, catalogues violations, fixes them
#   4. Verifies the full chain passes before pushing
#   5. Reports outcome
#
# MODEL: opencode/mimo-v2.5-free (free tier, operative shim applied)
# SHIM:  intent-shims/operative.mimo.md (commit-discipline + scope-lock)
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SYNDICATE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OPERATIVE_SHIM="$SYNDICATE_ROOT/intent-shims/operative.mimo.md"

# ── Args ──────────────────────────────────────────────────────────────────────

PR_NUMBER="${1:-}"
CI_FACTS_FILE="${2:-}"

if [[ -z "$PR_NUMBER" ]]; then
  echo "Usage: branch-hygiene.sh <PR_NUMBER> [CI_FACTS_FILE]" >&2
  exit 1
fi

if [[ ! -f "$OPERATIVE_SHIM" ]]; then
  echo "ERROR: operative shim not found at $OPERATIVE_SHIM" >&2
  exit 1
fi

if [[ -n "$CI_FACTS_FILE" && ! -f "$CI_FACTS_FILE" ]]; then
  echo "ERROR: CI facts file not found: $CI_FACTS_FILE" >&2
  exit 1
fi

# ── Derive repo from git remote ───────────────────────────────────────────────

REPO=$(git remote get-url origin 2>/dev/null \
  | sed -E 's|.*github\.com[:/]||; s|\.git$||') || true

if [[ -z "$REPO" ]]; then
  echo "ERROR: could not derive GitHub repo from git remote. Run from inside the repo." >&2
  exit 1
fi

# ── Protocol (embedded) ───────────────────────────────────────────────────────

PROTOCOL=$(cat <<'PROTO'
## BRANCH HYGIENE PROTOCOL

You are investigating and remediating branch health for a GitHub PR.
Follow every step in order. Every step has a decision gate — match the
outcome against the FAILURE CLASSES table and apply the prescribed response.
Do not skip steps. Do not improvise outside the prescribed responses.

### STEP 1 — Check CI status

```
gh pr checks <PR_NUMBER> --repo <REPO>
```

Outcomes:
- All checks passing → DONE. Report green and exit.
- One or more checks failing → proceed to STEP 3.
- No checks reported → proceed to STEP 2.

### STEP 2 — Diagnose why CI never fired

```
gh api repos/<REPO>/pulls/<PR_NUMBER> \
  --jq '{mergeable: .mergeable, base: .base.ref, head: .head.ref}'
gh run list --branch <HEAD_BRANCH> --repo <REPO> --limit 5
```

Then check for stale commits:
```
git fetch origin
git log origin/<BASE_BRANCH>..<HEAD_BRANCH> --oneline
git log <HEAD_BRANCH>..origin/<BASE_BRANCH> --oneline
```

Match against FAILURE CLASSES table.

### STEP 3 — Run full local CI chain

Read the CI FACTS block (appended below) for the exact commands.
Run EVERY tool in the chain regardless of earlier failures.
Capture exit code and all output for each tool.
Do NOT stop at the first failure — catalogue ALL violations before fixing anything.

### STEP 4 — Fix all violations

Fix every violation identified in STEP 3. Apply fixes in this order:
backend linting/formatting → backend type errors → architecture violations →
dependency sync → frontend linting → frontend type errors.

After ALL fixes are applied, proceed to STEP 5.
Do NOT verify a single tool and commit — verify the full chain.

### STEP 5 — Verify full chain

Re-run every tool from STEP 3. Every tool must exit 0.
If any tool still fails, fix it and re-run the full chain again.
Do not commit until the complete chain is green.

### STEP 6 — Commit and push

```
git add <only the files you changed>
git commit -m "fix(ci): resolve <summary of all violations fixed>"
git push origin <HEAD_BRANCH>
```

If the fix for CI-never-fired was a rebase:
```
git push origin <HEAD_BRANCH> --force-with-lease
```

### STEP 7 — Report

Return:
- What CI showed (or why it hadn't fired)
- Every violation found and which file it was in
- Every file changed and what was changed
- Full chain exit codes after fix
- Commit SHA(s) created

---

## FAILURE CLASSES — symptom → prescribed response

| # | Class | Symptom | Response |
|---|-------|---------|----------|
| 1 | Stale pre-merge commits | `mergeable: false`; `git log origin/main..HEAD` includes commits already merged to main as a squash/merge commit | `git rebase origin/<BASE_BRANCH>` — git will drop already-upstream patches automatically. Then `git push --force-with-lease`. |
| 2 | Branch behind main | CI triggered but base has moved; `git log HEAD..origin/<BASE_BRANCH>` is non-empty | `git rebase origin/<BASE_BRANCH>`. Then `git push --force-with-lease`. |
| 3 | Merge conflict during rebase | `CONFLICT` lines in rebase output | STOP AND REPORT the conflicting files verbatim. Do not attempt to resolve merge conflicts. |
| 4 | CI failed — lint/type/arch violations | Non-zero exit from ruff / mypy / tsc / validate_architecture.py / etc. | Run full chain (STEP 3), fix all, verify all (STEP 5), then commit + push. |
| 5 | No workflow runs + mergeable | CI workflow exists but never fired despite clean merge state | Push an empty commit: `git commit --allow-empty -m "ci: trigger workflow"` then `git push`. |
| 6 | Unclassified failure | Does not match any class above | STOP AND REPORT the verbatim error text and the step at which it occurred. |
PROTO
)

# ── Substitute PR_NUMBER and REPO into protocol ───────────────────────────────

PROTOCOL="${PROTOCOL//<PR_NUMBER>/$PR_NUMBER}"
PROTOCOL="${PROTOCOL//<REPO>/$REPO}"

# ── Build pi args ─────────────────────────────────────────────────────────────

PI_ARGS=(
  --print
  --no-session
  --model opencode/mimo-v2.5-free
  --append-system-prompt "$OPERATIVE_SHIM"
)

# Append CI facts file if provided
if [[ -n "$CI_FACTS_FILE" ]]; then
  PI_ARGS+=(--append-system-prompt "$CI_FACTS_FILE")
fi

# ── Launch ────────────────────────────────────────────────────────────────────

echo "[branch-hygiene] PR #$PR_NUMBER · repo: $REPO" >&2
[[ -n "$CI_FACTS_FILE" ]] && echo "[branch-hygiene] CI facts: $CI_FACTS_FILE" >&2
echo "" >&2

pi "${PI_ARGS[@]}" "$PROTOCOL"
