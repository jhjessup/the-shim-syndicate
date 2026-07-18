#!/usr/bin/env bash
# =============================================================================
# sync-governance.sh — Auto-Capture Central Governance Changes
# =============================================================================
# Version: 1.0.0
# Repository: jhjessup/the-shim-syndicate
#
# DESCRIPTION:
#   Ensures governance data is captured regardless of which repo it's
#   attached to. Called by hooks/post-commit and hooks/post-merge in every
#   downstream project using centralized governance (.syndicate is a symlink
#   — see syndicate-init.sh --governance central). After any commit or merge
#   in the downstream repo, this script:
#     1. Resolves .syndicate — if it's not a symlink (colocated mode, or no
#        governance at all), does nothing and exits 0.
#     2. Resolves the symlink target's containing git repo (the central
#        governance repo, e.g. syndicate-projects).
#     3. If that repo has uncommitted changes, stages, commits (referencing
#        the downstream repo/branch/commit that triggered this), and — unless
#        SYNDICATE_GOVERNANCE_NO_PUSH=1 — pushes.
#
#   CRITICAL DESIGN CONSTRAINT: this script must NEVER cause the calling git
#   hook to fail the parent commit/merge. A governance-sync problem (network
#   down, central repo dirty with unrelated conflicts, no push access) must
#   never block the developer's actual work. Every failure path here logs a
#   clear warning and exits 0.
#
# USAGE:
#   bash sync-governance.sh [DOWNSTREAM_REPO_DIR]
#   (default: current directory, resolved via git rev-parse --show-toplevel)
#
# ENVIRONMENT VARIABLES:
#   SYNDICATE_GOVERNANCE_NO_PUSH=1   Commit locally only, skip the push.
#   SYNDICATE_GOVERNANCE_SYNC_QUIET=1  Suppress non-warning output (hooks set
#                                      this by default; run manually without
#                                      it for verbose diagnostics).
#
# EXIT CODES:
#   Always 0. This script reports problems via stderr warnings, never via
#   exit code — callers (hooks) must not branch on it or treat it as gating.
# =============================================================================
set -uo pipefail
# NOTE: deliberately NOT `set -e` — every step here must degrade to a warning,
# never abort partway leaving unclear state, and never propagate a failure
# exit code to the calling hook.

RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
RESET='\033[0m'

QUIET="${SYNDICATE_GOVERNANCE_SYNC_QUIET:-0}"

log_info() { [[ "$QUIET" == "1" ]] || echo -e "${CYAN}[SYNC-GOV]${RESET} $*"; }
log_ok()   { [[ "$QUIET" == "1" ]] || echo -e "${GREEN}[SYNC-GOV]${RESET} $*"; }
log_warn() { echo -e "${YELLOW}[SYNC-GOV]${RESET} $*" >&2; }  # warnings always show

DOWNSTREAM_REPO_DIR="${1:-$(pwd)}"

# -----------------------------------------------------------------------------
# Step 1: Resolve the downstream repo root and its .syndicate path.
# -----------------------------------------------------------------------------
DOWNSTREAM_ROOT="$(git -C "$DOWNSTREAM_REPO_DIR" rev-parse --show-toplevel 2>/dev/null)"
if [[ -z "$DOWNSTREAM_ROOT" ]]; then
  log_warn "Could not resolve a git repo root from '$DOWNSTREAM_REPO_DIR' — skipping sync."
  exit 0
fi

SYNDICATE_PATH="$DOWNSTREAM_ROOT/.syndicate"

if [[ ! -L "$SYNDICATE_PATH" ]]; then
  # Not central mode (colocated, or no governance at all) — nothing to sync
  # externally; the downstream repo's own commit already captured it (or
  # there's genuinely nothing to capture).
  log_info "$SYNDICATE_PATH is not a symlink — colocated or no governance. Nothing to sync."
  exit 0
fi

CENTRAL_GOVERNANCE_ROOT="$(readlink "$SYNDICATE_PATH")"
if [[ ! -d "$CENTRAL_GOVERNANCE_ROOT" ]]; then
  log_warn ".syndicate symlink target does not exist: $CENTRAL_GOVERNANCE_ROOT — skipping sync."
  exit 0
fi

# -----------------------------------------------------------------------------
# Step 2: Resolve the central repo root (the git repository CONTAINING the
# governance directory — may be the governance directory's parent, e.g.
# syndicate-projects/<project>/ where syndicate-projects/ is the repo root).
# -----------------------------------------------------------------------------
CENTRAL_REPO_ROOT="$(git -C "$CENTRAL_GOVERNANCE_ROOT" rev-parse --show-toplevel 2>/dev/null)"
if [[ -z "$CENTRAL_REPO_ROOT" ]]; then
  log_warn "$CENTRAL_GOVERNANCE_ROOT is not inside a git repository — cannot sync. Fix manually."
  exit 0
fi

# -----------------------------------------------------------------------------
# Step 3: Check for changes. If none, nothing to do.
# -----------------------------------------------------------------------------
if [[ -z "$(git -C "$CENTRAL_REPO_ROOT" status --porcelain 2>/dev/null)" ]]; then
  log_info "No pending changes in $CENTRAL_REPO_ROOT — nothing to sync."
  exit 0
fi

# -----------------------------------------------------------------------------
# Step 4: Build a commit message referencing the triggering downstream event.
# -----------------------------------------------------------------------------
DOWNSTREAM_PROJECT="$(basename "$DOWNSTREAM_ROOT")"
DOWNSTREAM_BRANCH="$(git -C "$DOWNSTREAM_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")"
DOWNSTREAM_SHA="$(git -C "$DOWNSTREAM_ROOT" rev-parse --short HEAD 2>/dev/null || echo "unknown")"

COMMIT_MSG="auto-sync: governance update from ${DOWNSTREAM_PROJECT}@${DOWNSTREAM_SHA} (branch: ${DOWNSTREAM_BRANCH})"

# -----------------------------------------------------------------------------
# Step 5: Stage, commit. Scope the add to the specific project's governance
# directory plus the top-level README (in case a project-registration edit is
# pending) — never a blind `git add -A`, which could sweep in another
# project's in-progress, unrelated changes sitting in the same central repo.
# -----------------------------------------------------------------------------
PROJECT_SUBDIR="${CENTRAL_GOVERNANCE_ROOT#"$CENTRAL_REPO_ROOT"/}"

(
  cd "$CENTRAL_REPO_ROOT" || exit 0
  git add "$PROJECT_SUBDIR/" 2>/dev/null
  # README.md at the repo root is a reasonable, narrowly-scoped inclusion
  # (project registration table) — anything else in the central repo outside
  # this project's own subdirectory is deliberately left untouched.
  [[ -f "README.md" ]] && git add README.md 2>/dev/null

  if git diff --cached --quiet 2>/dev/null; then
    log_info "Nothing staged for $PROJECT_SUBDIR after scoping — skipping commit."
    exit 0
  fi

  if git commit -m "$COMMIT_MSG" >/dev/null 2>&1; then
    log_ok "Committed governance sync in $CENTRAL_REPO_ROOT ($PROJECT_SUBDIR)"
  else
    log_warn "git commit failed in $CENTRAL_REPO_ROOT — governance changes remain staged, not lost. Investigate manually."
    exit 0
  fi

  if [[ "${SYNDICATE_GOVERNANCE_NO_PUSH:-0}" == "1" ]]; then
    log_info "SYNDICATE_GOVERNANCE_NO_PUSH=1 — committed locally only, did not push."
    exit 0
  fi

  CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")"
  if [[ -z "$CURRENT_BRANCH" || "$CURRENT_BRANCH" == "HEAD" ]]; then
    log_warn "Central repo is in a detached-HEAD state — committed locally, skipped push. Investigate manually."
    exit 0
  fi

  if git push origin "$CURRENT_BRANCH" >/dev/null 2>&1; then
    log_ok "Pushed governance sync to origin/$CURRENT_BRANCH"
  else
    log_warn "Push failed (no network? no remote? auth issue? diverged from origin?) — commit is safe locally in $CENTRAL_REPO_ROOT, but NOT yet backed up remotely. Push manually: cd $CENTRAL_REPO_ROOT && git push"
  fi
)

exit 0
