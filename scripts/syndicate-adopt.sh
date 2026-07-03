#!/usr/bin/env bash
# =============================================================================
# syndicate-adopt.sh — Bring an Existing Repo Under Syndicate Governance
# =============================================================================
# Version: 1.0.0
# Repository: jhjessup/the-shim-syndicate
#
# DESCRIPTION:
#   One-shot adoption of an already-existing git repository (e.g. one created
#   mid-mission) into The Shim Syndicate's governance model. It wires the
#   Gavel git hooks via core.hooksPath so commits are gated (branch guard +
#   audit-trace trailer), and seeds a project-map.json into an existing
#   .syndicate/ stub if one is missing. It deliberately does NOT fabricate a
#   full .syndicate/ stub — run syndicate-init.sh for a first-time hydration.
#
# USAGE:
#   bash syndicate-adopt.sh [REPO_DIR] [OPTIONS]
#
# ARGUMENTS:
#   REPO_DIR    Path to the git repository to adopt (default: current dir)
#
# OPTIONS:
#   --dry-run   Preview all actions without executing them
#   --help, -h  Show this help message
#
# ENVIRONMENT VARIABLES:
#   SYNDICATE_CORE_PATH   Override the auto-detected Syndicate Core path
#
# EXAMPLES:
#   bash syndicate-adopt.sh
#   bash syndicate-adopt.sh ../some-mid-mission-repo
#   bash syndicate-adopt.sh /path/to/repo --dry-run
#
# =============================================================================
set -euo pipefail

# -----------------------------------------------------------------------------
# Constants
# -----------------------------------------------------------------------------
SCRIPT_VERSION="1.0.0"
SYNDICATE_DIR=".syndicate"

# ANSI color codes
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# -----------------------------------------------------------------------------
# Logging helpers
# -----------------------------------------------------------------------------
log_info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
log_ok()      { echo -e "${GREEN}[OK]${RESET}    $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
log_error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; }
log_section() { echo -e "\n${BOLD}── $* ──${RESET}"; }
dry_run_echo(){ echo -e "${YELLOW}[DRY-RUN]${RESET} Would execute: $*"; }

# -----------------------------------------------------------------------------
# Core path resolution — this script lives in <core>/scripts/, so CORE_PATH is
# its parent directory (overridable via SYNDICATE_CORE_PATH).
# -----------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE_PATH="${SYNDICATE_CORE_PATH:-$(cd "$SCRIPT_DIR/.." && pwd)}"

# -----------------------------------------------------------------------------
# Defaults
# -----------------------------------------------------------------------------
REPO_DIR="$(pwd)"
DRY_RUN=false

# -----------------------------------------------------------------------------
# Help
# -----------------------------------------------------------------------------
usage() {
  grep '^#' "$0" | grep -v '#!/' | sed 's/^# \{0,2\}//' | sed 's/^#//'
  exit 0
}

# -----------------------------------------------------------------------------
# Argument parsing
# -----------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)   DRY_RUN=true;   shift ;;
    --help|-h)   usage ;;
    -*) log_error "Unknown option: $1"; exit 1 ;;
    *)  REPO_DIR="$1"; shift ;;
  esac
done

# -----------------------------------------------------------------------------
# Helper: Execute or dry-run a command
# -----------------------------------------------------------------------------
exec_or_dry() {
  if [[ "$DRY_RUN" == true ]]; then
    dry_run_echo "$*"
  else
    eval "$*"
  fi
}

# -----------------------------------------------------------------------------
# Pre-flight
# -----------------------------------------------------------------------------
log_section "Syndicate Adoption v${SCRIPT_VERSION}"

if [[ "$DRY_RUN" == true ]]; then
  log_warn "DRY-RUN MODE — no changes will be made."
fi

# Verify the Core hooks directory is present
if [[ ! -d "$CORE_PATH/hooks" ]]; then
  log_error "Syndicate Core hooks not found at $CORE_PATH/hooks"
  log_error "Set SYNDICATE_CORE_PATH or run this script from within the Core's scripts/ dir."
  exit 1
fi
log_ok "Syndicate Core: $CORE_PATH"

# -----------------------------------------------------------------------------
# Step 1: Verify REPO_DIR is a git work tree
# -----------------------------------------------------------------------------
log_section "Step 1: Verifying Git Work Tree"

if [[ ! -d "$REPO_DIR" ]]; then
  log_error "REPO_DIR does not exist: $REPO_DIR"
  exit 1
fi

if [[ "$(git -C "$REPO_DIR" rev-parse --is-inside-work-tree 2>/dev/null || echo false)" != "true" ]]; then
  log_error "Not a git work tree: $REPO_DIR"
  log_error "Run 'git init' there first, or pass a valid repository path."
  exit 1
fi

REPO_ROOT="$(git -C "$REPO_DIR" rev-parse --show-toplevel)"
log_ok "Git work tree confirmed: $REPO_ROOT"

# -----------------------------------------------------------------------------
# Step 2: Wire Gavel git hooks (core.hooksPath)
# -----------------------------------------------------------------------------
log_section "Step 2: Wiring Gavel Git Hooks (core.hooksPath)"

exec_or_dry "git -C '$REPO_ROOT' config core.hooksPath '$CORE_PATH/hooks'"
[[ "$DRY_RUN" == true ]] || log_ok "Wired git hooks → $CORE_PATH/hooks (core.hooksPath)"

# -----------------------------------------------------------------------------
# Step 3: Ensure a .syndicate/ stub exists at the repo root
# -----------------------------------------------------------------------------
log_section "Step 3: Checking .syndicate/ Stub"

STUB_DIR="$REPO_ROOT/$SYNDICATE_DIR"
STUB_PRESENT=false

if [[ -d "$STUB_DIR" ]]; then
  STUB_PRESENT=true
  log_ok ".syndicate/ stub present: $STUB_DIR"
else
  log_warn "No .syndicate/ stub found at $STUB_DIR"
  log_warn "This script does not fabricate a full stub. Hydrate the repo first:"
  log_warn "  cd '$REPO_ROOT' && bash '$SCRIPT_DIR/syndicate-init.sh' --core '$CORE_PATH'"
fi

# -----------------------------------------------------------------------------
# Step 4: Seed project-map.json if the stub exists but lacks one
# -----------------------------------------------------------------------------
log_section "Step 4: Seeding project-map.json"

MAP_TEMPLATE="$CORE_PATH/templates/project-map.json"
MAP_DEST="$STUB_DIR/project-map.json"

if [[ "$STUB_PRESENT" != true ]]; then
  log_info "Skipping project-map.json seed (no .syndicate/ stub)."
elif [[ -f "$MAP_DEST" ]]; then
  log_ok "project-map.json already present → $MAP_DEST"
elif [[ ! -f "$MAP_TEMPLATE" ]]; then
  log_warn "project-map.json template not found at $MAP_TEMPLATE — cannot seed."
else
  # Derive a sensible project name from the repo root directory.
  PROJECT_NAME="$(basename "$REPO_ROOT")"
  ESC_PROJECT="$(printf '%s' "$PROJECT_NAME" | sed -e 's/[&/\\]/\\&/g')"
  MAP_DATE="$(date -u +%Y-%m-%d)"
  SYNDICATE_VERSION="unknown"
  if [[ -f "$CORE_PATH/manifest.json" ]] && command -v jq &>/dev/null; then
    SYNDICATE_VERSION="$(jq -r '.active_version // "unknown"' "$CORE_PATH/manifest.json")"
  fi

  if [[ "$DRY_RUN" == false ]]; then
    sed \
      -e "s/{{MISSION_NAME}}/$ESC_PROJECT/g" \
      -e "s/{{MISSION_DATE}}/$MAP_DATE/g" \
      -e "s/{{SYNDICATE_VERSION}}/$SYNDICATE_VERSION/g" \
      -e "s/{{PROJECT_NAME}}/$ESC_PROJECT/g" \
      "$MAP_TEMPLATE" > "$MAP_DEST"
    log_ok "Seeded project-map.json → $MAP_DEST"
    log_info "Ask The Ledger to populate structure, dependencies, and prior_decisions."
  else
    dry_run_echo "sed [template substitution] '$MAP_TEMPLATE' → '$MAP_DEST'"
  fi
fi

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------
log_section "Adoption Summary"
echo ""
echo -e "  ${BOLD}Repository:${RESET}   $REPO_ROOT"
echo -e "  ${BOLD}Core:${RESET}         $CORE_PATH"
echo -e "  ${BOLD}Hooks:${RESET}        core.hooksPath → $CORE_PATH/hooks"
echo -e "  ${BOLD}Stub:${RESET}         $([ "$STUB_PRESENT" == true ] && echo "$STUB_DIR" || echo "MISSING — run syndicate-init.sh")"
echo ""
log_warn "core.hooksPath is LOCAL git config — it is not cloned. Re-run this script"
log_warn "(bash syndicate-adopt.sh) after every fresh clone to re-arm The Gavel."
echo ""
log_info "If this script is not executable, make it so:  chmod +x '$SCRIPT_DIR/syndicate-adopt.sh'"
echo ""
