#!/usr/bin/env bash
# =============================================================================
# syndicate-init.sh — The Shim Syndicate Project Hydration Script
# =============================================================================
# Version: 2.1.0
# Repository: jhjessup/the-shim-syndicate
#
# DESCRIPTION:
#   Hydrates a new or existing project repository with The Shim Syndicate
#   agent team. Creates a local .syndicate/ stub, links the Syndicate Core,
#   generates a project-specific ORACLE.md and project-map.json, initializes
#   the AUDIT_LOG.md, and wires the Gavel git hooks by pointing the repo's
#   core.hooksPath at the Core's shared hooks directory.
#
#   With --mission: Operates in Mission Mode. Verifies the current branch is a
#   mission/ branch, creates a branch-isolated vault at
#   .syndicate/vault/<branch-name>/, generates a Mission Brief, copies the
#   ORACLE.md and project-map.json templates into the vault, and wires the
#   Gavel git hooks (pre-commit and commit-msg) by setting core.hooksPath to
#   the Core's hooks directory. Hook wiring runs in both modes.
#
# USAGE:
#   cd /path/to/your-project
#   bash /path/to/syndicate-init.sh [OPTIONS]
#
# OPTIONS:
#   --mode        Integration mode: 'symlink' (default) or 'subtree'
#   --shim        Shim config to use: 'claude' (default), 'gemini', 'local', or 'pi'
#   --governance  Where .syndicate/ governance data lives: 'central' or 'colocated'.
#                 'central' (RECOMMENDED, default for fresh hydrations): governance
#                 (ORACLE.md, TEST_DOCTRINE.md, routing.json, config.json, vault/)
#                 lives in $SYNDICATE_PROJECTS_PATH/<project>/, and the project root
#                 gets a .syndicate symlink pointing there — the project's own code
#                 repo never commits governance data. This is the pattern
#                 concierge-hub and mcp-gateway both use.
#                 'colocated': governance lives at <project-root>/.syndicate/ and is
#                 committed directly into the project's own repo (the original,
#                 pre-2026-07-18 default — kept for standalone repos that don't want
#                 an external governance store).
#                 If omitted, this script AUTO-DETECTS from the existing .syndicate
#                 path: a symlink → central (reusing its exact target, not
#                 recomputing one); a real directory → colocated (preserves
#                 whatever the project already uses); neither exists → central (the
#                 default for brand-new projects).
#   --operator    Operator name for audit records (quoted string)
#   --project     Project name (defaults to current directory name)
#   --core        Path to the Syndicate Core repo (required if not set via env)
#   --mission     Run in Mission Mode: initialize a branch-specific vault
#   --yes, -y     Assume "yes" to all confirmation prompts (non-interactive)
#   --dry-run     Preview all actions without executing them
#   --help        Show this help message
#
# ENVIRONMENT VARIABLES:
#   SYNDICATE_CORE_PATH      Path to the cloned Syndicate Core repository
#   SYNDICATE_DEFAULT_SHIM   Default shim to use (claude | gemini | local | pi)
#   SYNDICATE_PROJECTS_PATH  Path to the central governance repo (default: $HOME/syndicate-projects).
#                            Must already exist as a git repository — this script
#                            does not create or `git init` it for you.
#
# EXAMPLES:
#   bash syndicate-init.sh --operator "Jane Smith" --shim claude
#   SYNDICATE_CORE_PATH=~/syndicate bash syndicate-init.sh --mode subtree
#   bash syndicate-init.sh --mission --operator "Jane Smith"
#   bash syndicate-init.sh --governance colocated   # opt out of the central store
#
# =============================================================================
set -euo pipefail

# -----------------------------------------------------------------------------
# Constants
# -----------------------------------------------------------------------------
SCRIPT_VERSION="2.2.0"
SYNDICATE_DIR=".syndicate"
REQUIRED_COMMANDS=("git" "jq")
OPTIONAL_COMMANDS=("claude" "gemini" "ollama" "opencode")
SYNDICATE_PROJECTS_PATH="${SYNDICATE_PROJECTS_PATH:-$HOME/syndicate-projects}"

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

# Escape a value for safe use as a sed substitution replacement (handles & / \)
sed_escape() { printf '%s' "$1" | sed -e 's/[&/\\]/\\&/g'; }

# -----------------------------------------------------------------------------
# Default values
# -----------------------------------------------------------------------------
MODE="symlink"
SHIM="claude"
GOVERNANCE=""   # empty = auto-detect (see header docs)
OPERATOR="${SYNDICATE_OPERATOR:-}"
PROJECT_NAME=""
CORE_PATH="${SYNDICATE_CORE_PATH:-}"
DRY_RUN=false
MISSION_MODE=false
ASSUME_YES=false
PROJECT_DIR="$(pwd)"

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
    --mode)        MODE="$2";         shift 2 ;;
    --shim)        SHIM="$2";         shift 2 ;;
    --governance)  GOVERNANCE="$2";   shift 2 ;;
    --operator)    OPERATOR="$2";     shift 2 ;;
    --project)   PROJECT_NAME="$2"; shift 2 ;;
    --core)      CORE_PATH="$2";    shift 2 ;;
    --mission)   MISSION_MODE=true; shift   ;;
    --yes|-y)    ASSUME_YES=true;   shift   ;;
    --dry-run)   DRY_RUN=true;      shift   ;;
    --help|-h)   usage ;;
    *) log_error "Unknown option: $1"; exit 1 ;;
  esac
done

# -----------------------------------------------------------------------------
# Derived values
# -----------------------------------------------------------------------------
if [[ -z "$PROJECT_NAME" ]]; then
  PROJECT_NAME="$(basename "$PROJECT_DIR")"
fi

HYDRATION_DATE="$(date -u +%Y-%m-%d)"
HYDRATION_TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# -----------------------------------------------------------------------------
# Governance mode resolution
# -----------------------------------------------------------------------------
# CENTRAL_GOVERNANCE_ROOT is only meaningful when GOVERNANCE=central; it is the
# actual filesystem location of the governance data (what STUB_DIR points at in
# Step 1). Auto-detection reuses an EXISTING project's exact symlink target
# rather than recomputing $SYNDICATE_PROJECTS_PATH/$PROJECT_NAME fresh, so a
# project set up with a nonstandard central path is never silently redirected.
EXISTING_SYNDICATE_PATH="$PROJECT_DIR/$SYNDICATE_DIR"
CENTRAL_GOVERNANCE_ROOT=""

if [[ -z "$GOVERNANCE" ]]; then
  if [[ -L "$EXISTING_SYNDICATE_PATH" ]]; then
    GOVERNANCE="central"
    CENTRAL_GOVERNANCE_ROOT="$(cd "$(dirname "$EXISTING_SYNDICATE_PATH")" && readlink -f "$SYNDICATE_DIR" 2>/dev/null || readlink "$EXISTING_SYNDICATE_PATH")"
    log_info "Auto-detected governance mode: central (existing .syndicate symlink → $CENTRAL_GOVERNANCE_ROOT)"
  elif [[ -d "$EXISTING_SYNDICATE_PATH" ]]; then
    GOVERNANCE="colocated"
    log_info "Auto-detected governance mode: colocated (existing .syndicate/ is a real directory)"
  else
    GOVERNANCE="central"
    log_info "No existing .syndicate found — defaulting to governance mode: central"
  fi
else
  if [[ "$GOVERNANCE" != "central" && "$GOVERNANCE" != "colocated" ]]; then
    log_error "Invalid --governance value: '$GOVERNANCE'. Must be 'central' or 'colocated'."
    exit 1
  fi
  # Explicit flag conflicting with an existing setup is almost always a mistake
  # (e.g. re-running with --governance colocated on a project already migrated
  # to central would silently re-materialize real files where a symlink was) —
  # refuse rather than guess.
  if [[ "$GOVERNANCE" == "colocated" && -L "$EXISTING_SYNDICATE_PATH" ]]; then
    log_error "--governance colocated was passed, but .syndicate is already a symlink to $(readlink "$EXISTING_SYNDICATE_PATH")."
    log_error "Overwriting it would silently abandon the existing central governance data."
    log_error "If you really want to de-migrate, remove the symlink manually first."
    exit 1
  fi
  if [[ "$GOVERNANCE" == "central" && -d "$EXISTING_SYNDICATE_PATH" && ! -L "$EXISTING_SYNDICATE_PATH" ]]; then
    log_error "--governance central was passed, but .syndicate already exists as a real (colocated) directory."
    log_error "Use scripts/syndicate-migrate-governance.sh to migrate existing governance data safely —"
    log_error "this script will not silently move/discard it."
    exit 1
  fi
  if [[ "$GOVERNANCE" == "central" ]]; then
    if [[ -L "$EXISTING_SYNDICATE_PATH" ]]; then
      CENTRAL_GOVERNANCE_ROOT="$(readlink "$EXISTING_SYNDICATE_PATH")"
    else
      CENTRAL_GOVERNANCE_ROOT="$SYNDICATE_PROJECTS_PATH/$PROJECT_NAME"
    fi
  fi
fi

if [[ "$GOVERNANCE" == "central" && -z "$CENTRAL_GOVERNANCE_ROOT" ]]; then
  CENTRAL_GOVERNANCE_ROOT="$SYNDICATE_PROJECTS_PATH/$PROJECT_NAME"
fi

# CENTRAL_REPO_ROOT is the actual central git repository directory — always
# derived from CENTRAL_GOVERNANCE_ROOT (which may have come from
# auto-detecting an EXISTING symlink pointing somewhere other than
# $SYNDICATE_PROJECTS_PATH), never read from $SYNDICATE_PROJECTS_PATH
# directly. Using the raw env var here would silently target the wrong repo
# for any project whose central store lives at a nonstandard path — verified
# by a real bug caught in testing (an unset/mismatched SYNDICATE_PROJECTS_PATH
# caused a registration write into the WRONG central repo even though
# CENTRAL_GOVERNANCE_ROOT itself was correctly auto-detected).
if [[ "$GOVERNANCE" == "central" ]]; then
  CENTRAL_REPO_ROOT="$(dirname "$CENTRAL_GOVERNANCE_ROOT")"
fi

# -----------------------------------------------------------------------------
# Pre-flight checks
# -----------------------------------------------------------------------------
log_section "Pre-flight Checks"

# Check required commands
for cmd in "${REQUIRED_COMMANDS[@]}"; do
  if ! command -v "$cmd" &>/dev/null; then
    log_error "Required command not found: '$cmd'. Install it before proceeding."
    exit 1
  fi
  log_ok "Found required command: $cmd"
done

# Check optional commands (warn only)
for cmd in "${OPTIONAL_COMMANDS[@]}"; do
  if command -v "$cmd" &>/dev/null; then
    log_ok "Found optional command: $cmd"
  else
    log_warn "Optional command not found: '$cmd' — some shim backends will be unavailable"
  fi
done

# Verify we are in a git repository
if ! git rev-parse --git-dir &>/dev/null; then
  log_error "Not a git repository. Run 'git init' first or navigate to a valid repo."
  exit 1
fi
log_ok "Git repository detected."

# Validate mode
if [[ "$MODE" != "symlink" && "$MODE" != "subtree" ]]; then
  log_error "Invalid --mode value: '$MODE'. Must be 'symlink' or 'subtree'."
  exit 1
fi

# Validate shim
if [[ "$SHIM" != "claude" && "$SHIM" != "gemini" && "$SHIM" != "local" && "$SHIM" != "pi" ]]; then
  log_error "Invalid --shim value: '$SHIM'. Must be 'claude', 'gemini', 'local', or 'pi'."
  exit 1
fi

# Check Syndicate Core path
if [[ -z "$CORE_PATH" ]]; then
  log_error "Syndicate Core path not set. Use --core /path/to/syndicate or set SYNDICATE_CORE_PATH."
  exit 1
fi

if [[ ! -d "$CORE_PATH" ]]; then
  log_error "Syndicate Core path does not exist: $CORE_PATH"
  exit 1
fi

if [[ ! -f "$CORE_PATH/manifest.json" ]]; then
  log_error "Path '$CORE_PATH' does not appear to be a valid Syndicate Core (manifest.json not found)."
  exit 1
fi
log_ok "Syndicate Core found: $CORE_PATH"

# Check central governance path (central mode only) — validates
# CENTRAL_REPO_ROOT (the actual resolved repo, honoring auto-detection of an
# existing nonstandard symlink target), NOT the raw SYNDICATE_PROJECTS_PATH
# env var, which may not match it.
if [[ "$GOVERNANCE" == "central" ]]; then
  if [[ ! -d "$CENTRAL_REPO_ROOT" ]]; then
    log_error "Central governance path does not exist: $CENTRAL_REPO_ROOT"
    log_error "Create/clone it first (it must be a git repository), or set SYNDICATE_PROJECTS_PATH,"
    log_error "or pass --governance colocated to opt out of central governance for this project."
    exit 1
  fi
  if [[ "$(git -C "$CENTRAL_REPO_ROOT" rev-parse --is-inside-work-tree 2>/dev/null || echo false)" != "true" ]]; then
    log_error "$CENTRAL_REPO_ROOT exists but is not a git repository."
    exit 1
  fi
  log_ok "Central governance repo found: $CENTRAL_REPO_ROOT"
fi

# Read syndicate version from manifest
SYNDICATE_VERSION="$(jq -r '.active_version' "$CORE_PATH/manifest.json")"
if [[ -z "$SYNDICATE_VERSION" || "$SYNDICATE_VERSION" == "null" ]]; then
  log_error "Could not read active_version from $CORE_PATH/manifest.json"
  exit 1
fi
log_ok "Syndicate version: $SYNDICATE_VERSION"

# Operator name
if [[ -z "$OPERATOR" ]]; then
  # Try to get from git config
  OPERATOR="$(git config user.name 2>/dev/null || echo "")"
  if [[ -z "$OPERATOR" ]]; then
    log_warn "Operator name not set. Pass --operator 'Your Name' or configure git user.name."
    OPERATOR="Unknown Operator"
  fi
fi
log_ok "Operator: $OPERATOR"

# Check for existing hydration
if [[ -d "$PROJECT_DIR/$SYNDICATE_DIR" ]]; then
  log_warn "A .syndicate/ directory already exists in this project."
  if [[ "$ASSUME_YES" == true ]]; then
    log_info "--yes supplied — re-initializing without prompting."
  else
    read -r -p "  Re-initialize and overwrite? (y/N): " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
      log_info "Aborted by user."
      exit 0
    fi
  fi
fi

# -----------------------------------------------------------------------------
# Summary before execution
# -----------------------------------------------------------------------------
log_section "Hydration Plan"
echo -e "  ${BOLD}Project:${RESET}          $PROJECT_NAME"
echo -e "  ${BOLD}Project Path:${RESET}     $PROJECT_DIR"
echo -e "  ${BOLD}Core Path:${RESET}        $CORE_PATH"
echo -e "  ${BOLD}Mode:${RESET}             $MODE"
echo -e "  ${BOLD}Governance:${RESET}       $GOVERNANCE$([[ "$GOVERNANCE" == "central" ]] && echo " → $CENTRAL_GOVERNANCE_ROOT")"
echo -e "  ${BOLD}Shim:${RESET}             $SHIM"
echo -e "  ${BOLD}Syndicate Version:${RESET} $SYNDICATE_VERSION"
echo -e "  ${BOLD}Operator:${RESET}         $OPERATOR"
echo -e "  ${BOLD}Date:${RESET}             $HYDRATION_DATE"
echo ""

if [[ "$DRY_RUN" == true ]]; then
  log_warn "DRY-RUN MODE — no changes will be made."
fi

if [[ "$ASSUME_YES" == true ]]; then
  log_info "--yes supplied — proceeding without prompting."
else
  read -r -p "Proceed with hydration? (y/N): " confirm
  if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    log_info "Aborted by user."
    exit 0
  fi
fi

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
# Step 1: Create the governance directory structure
# -----------------------------------------------------------------------------
# STUB_DIR is where governance content actually lives on disk. In colocated
# mode that's $PROJECT_DIR/.syndicate itself. In central mode it's
# $CENTRAL_GOVERNANCE_ROOT (inside the syndicate-projects repo), and
# $PROJECT_DIR/.syndicate becomes a symlink pointing at it — every later step
# in this script writes to $STUB_DIR unchanged; only the symlink indirection
# and .gitignore/git-add handling differ by mode.
# -----------------------------------------------------------------------------
if [[ "$GOVERNANCE" == "central" ]]; then
  log_section "Step 1: Creating Central Governance Directory (mode: central)"
  STUB_DIR="$CENTRAL_GOVERNANCE_ROOT"
else
  log_section "Step 1: Creating .syndicate/ Directory (mode: colocated)"
  STUB_DIR="$PROJECT_DIR/$SYNDICATE_DIR"
fi

exec_or_dry "mkdir -p '$STUB_DIR'"
exec_or_dry "mkdir -p '$STUB_DIR/logs'"

log_ok "Created directory structure: $STUB_DIR"

if [[ "$GOVERNANCE" == "central" ]]; then
  LOCAL_SYNDICATE_PATH="$PROJECT_DIR/$SYNDICATE_DIR"
  if [[ -L "$LOCAL_SYNDICATE_PATH" ]]; then
    CURRENT_TARGET="$(readlink "$LOCAL_SYNDICATE_PATH")"
    if [[ "$CURRENT_TARGET" != "$STUB_DIR" ]]; then
      log_warn "Existing .syndicate symlink points at '$CURRENT_TARGET', not '$STUB_DIR' — replacing."
      exec_or_dry "rm '$LOCAL_SYNDICATE_PATH'"
      exec_or_dry "ln -s '$STUB_DIR' '$LOCAL_SYNDICATE_PATH'"
    else
      log_ok ".syndicate symlink already correct → $STUB_DIR"
    fi
  elif [[ -e "$LOCAL_SYNDICATE_PATH" ]]; then
    log_error "Refusing to overwrite: $LOCAL_SYNDICATE_PATH exists and is not a symlink."
    exit 1
  else
    exec_or_dry "ln -s '$STUB_DIR' '$LOCAL_SYNDICATE_PATH'"
    log_ok "Symlinked .syndicate → $STUB_DIR"
  fi
fi

# -----------------------------------------------------------------------------
# Step 2: Link or copy the Syndicate Core
# -----------------------------------------------------------------------------
log_section "Step 2: Integrating Syndicate Core (mode: $MODE)"

if [[ "$MODE" == "symlink" ]]; then
  LINK_TARGET="$STUB_DIR/core"
  if [[ -L "$LINK_TARGET" ]]; then
    exec_or_dry "rm '$LINK_TARGET'"
  fi
  exec_or_dry "ln -s '$CORE_PATH' '$LINK_TARGET'"
  log_ok "Symlinked Syndicate Core → $LINK_TARGET"
  log_info "Note: symlinks require the Core path to remain stable. For portability, use --mode subtree."

elif [[ "$MODE" == "subtree" ]]; then
  CORE_REMOTE_URL="$(git -C "$CORE_PATH" remote get-url origin 2>/dev/null || echo "")"
  if [[ -z "$CORE_REMOTE_URL" ]]; then
    log_warn "Could not detect remote URL for Syndicate Core. Falling back to local copy."
    exec_or_dry "cp -r '$CORE_PATH' '$STUB_DIR/core'"
    log_ok "Copied Syndicate Core → $STUB_DIR/core"
  else
    # Check if subtree is already added
    if git log --oneline --all --grep="Squashed '$SYNDICATE_DIR/core/'" | grep -q .; then
      log_info "Git subtree appears to already be present. Pulling latest."
      exec_or_dry "git subtree pull --prefix='$SYNDICATE_DIR/core' '$CORE_REMOTE_URL' main --squash"
    else
      exec_or_dry "git subtree add --prefix='$SYNDICATE_DIR/core' '$CORE_REMOTE_URL' main --squash"
    fi
    log_ok "Git subtree integrated: $SYNDICATE_DIR/core"
  fi
fi

# -----------------------------------------------------------------------------
# Step 3: Copy active shim configuration
# -----------------------------------------------------------------------------
log_section "Step 3: Installing Shim Configuration"

SHIM_SOURCE="$CORE_PATH/shims/${SHIM}.shim.json"
SHIM_DEST="$STUB_DIR/routing.json"

if [[ ! -f "$SHIM_SOURCE" ]]; then
  log_error "Shim file not found: $SHIM_SOURCE"
  exit 1
fi

exec_or_dry "cp '$SHIM_SOURCE' '$SHIM_DEST'"
log_ok "Installed shim config → $STUB_DIR/routing.json (source: ${SHIM}.shim.json)"

# -----------------------------------------------------------------------------
# Sed-safe substitution values (user-derived inputs escaped for sed replacement)
# -----------------------------------------------------------------------------
ESC_PROJECT="$(sed_escape "$PROJECT_NAME")"
ESC_OPERATOR="$(sed_escape "$OPERATOR")"

# -----------------------------------------------------------------------------
# Step 4: Generate ORACLE.md from template
# -----------------------------------------------------------------------------
log_section "Step 4: Generating ORACLE.md"

ORACLE_TEMPLATE="$CORE_PATH/templates/ORACLE.md"
ORACLE_DEST="$STUB_DIR/ORACLE.md"

if [[ ! -f "$ORACLE_TEMPLATE" ]]; then
  log_error "ORACLE.md template not found at: $ORACLE_TEMPLATE"
  exit 1
fi

# IDEMPOTENCY (verified-necessary fix, 2026-07-19): this project-level file is
# operator-edited content, not disposable scaffolding — re-running
# syndicate-init.sh (e.g. every `--mission` invocation, which is the normal,
# repeated way this script gets called across a project's lifetime) must
# never silently overwrite it. In central-governance mode this file IS the
# permanent record (no local-only draft state to discard changes from before
# committing), and the new auto-commit hooks can commit a blanked-out
# regeneration before anyone notices — this exact sequence destroyed 7
# completed tasks and 8 ADRs in a real project's governance history.
if [[ -f "$ORACLE_DEST" ]]; then
  log_info "ORACLE.md already exists at $ORACLE_DEST — leaving it untouched."
  log_info "Edit it directly, or delete it first if you intentionally want a fresh template."
elif [[ "$DRY_RUN" == false ]]; then
  sed \
    -e "s/{{PROJECT_NAME}}/$ESC_PROJECT/g" \
    -e "s/{{SYNDICATE_VERSION}}/$SYNDICATE_VERSION/g" \
    -e "s/{{HYDRATION_DATE}}/$HYDRATION_DATE/g" \
    -e "s/{{SHIM_FILE}}/${SHIM}.shim.json/g" \
    -e "s/{{OPERATOR_NAME}}/$ESC_OPERATOR/g" \
    "$ORACLE_TEMPLATE" > "$ORACLE_DEST"
  log_ok "Generated ORACLE.md → $ORACLE_DEST"
else
  dry_run_echo "sed [template substitution] '$ORACLE_TEMPLATE' → '$ORACLE_DEST'"
fi

# -----------------------------------------------------------------------------
# Step 4.1: Generate TEST_DOCTRINE.md from template
# -----------------------------------------------------------------------------
log_section "Step 4.1: Generating TEST_DOCTRINE.md"

DOCTRINE_TEMPLATE="$CORE_PATH/templates/TEST_DOCTRINE.md"
DOCTRINE_DEST="$STUB_DIR/TEST_DOCTRINE.md"

if [[ ! -f "$DOCTRINE_TEMPLATE" ]]; then
  log_warn "TEST_DOCTRINE.md template not found at: $DOCTRINE_TEMPLATE — skipping."
  log_warn "Test Doctrine will not be available until the template is present in Syndicate Core."
elif [[ -f "$DOCTRINE_DEST" ]]; then
  # IDEMPOTENCY — see the identical note on Step 4 (ORACLE.md) above.
  log_info "TEST_DOCTRINE.md already exists at $DOCTRINE_DEST — leaving it untouched."
else
  if [[ "$DRY_RUN" == false ]]; then
    sed \
      -e "s/{{PROJECT_NAME}}/$ESC_PROJECT/g" \
      -e "s/{{SYNDICATE_VERSION}}/$SYNDICATE_VERSION/g" \
      -e "s/{{HYDRATION_DATE}}/$HYDRATION_DATE/g" \
      -e "s/{{OPERATOR_NAME}}/$ESC_OPERATOR/g" \
      "$DOCTRINE_TEMPLATE" > "$DOCTRINE_DEST"
    log_ok "Generated TEST_DOCTRINE.md → $DOCTRINE_DEST"
    log_info "Complete all remaining {{placeholder}} sections in TEST_DOCTRINE.md before committing:"
    log_info "  §2.2  PROJECT_COMPOSABILITY_AXIOMS — Architecture-specific testability rules"
    log_info "  §3.1  COVERAGE_THRESHOLDS          — Per-layer numeric thresholds"
    log_info "  §3.2  MANDATORY_TEST_MATRIX        — Domain-specific required test behaviors"
  else
    dry_run_echo "sed [template substitution] '$DOCTRINE_TEMPLATE' → '$DOCTRINE_DEST'"
  fi
fi

# -----------------------------------------------------------------------------
# Step 4.2: Generate project-map.json from template
# -----------------------------------------------------------------------------
log_section "Step 4.2: Generating project-map.json"

MAP_TEMPLATE="$CORE_PATH/templates/project-map.json"
MAP_DEST="$STUB_DIR/project-map.json"

if [[ ! -f "$MAP_TEMPLATE" ]]; then
  log_warn "project-map.json template not found at: $MAP_TEMPLATE — skipping."
  log_warn "The Ledger will lack a project map until the template is present in Syndicate Core."
elif [[ -f "$MAP_DEST" ]]; then
  # IDEMPOTENCY — see the identical note on Step 4 (ORACLE.md) above. This one
  # matters most of all: project-map.json accumulates the task_queue and ADR
  # history across every mission a project has ever run. Blind regeneration
  # here is what actually destroyed a real project's task/ADR history.
  log_info "project-map.json already exists at $MAP_DEST — leaving it untouched."
else
  if [[ "$DRY_RUN" == false ]]; then
    sed \
      -e "s/{{MISSION_NAME}}/$ESC_PROJECT/g" \
      -e "s/{{MISSION_DATE}}/$HYDRATION_DATE/g" \
      -e "s/{{SYNDICATE_VERSION}}/$SYNDICATE_VERSION/g" \
      -e "s/{{PROJECT_NAME}}/$ESC_PROJECT/g" \
      "$MAP_TEMPLATE" > "$MAP_DEST"
    log_ok "Generated project-map.json → $MAP_DEST"
    log_info "Ask The Ledger to populate structure, dependencies, and prior_decisions before launching agents."
  else
    dry_run_echo "sed [template substitution] '$MAP_TEMPLATE' → '$MAP_DEST'"
  fi
fi

# -----------------------------------------------------------------------------
# Step 5: Initialize AUDIT_LOG.md
# -----------------------------------------------------------------------------
log_section "Step 5: Initializing AUDIT_LOG.md"

AUDIT_TEMPLATE="$CORE_PATH/templates/AUDIT_LOG.md"
AUDIT_DEST="$STUB_DIR/logs/AUDIT_LOG.md"

if [[ ! -f "$AUDIT_TEMPLATE" ]]; then
  log_error "AUDIT_LOG.md template not found at: $AUDIT_TEMPLATE"
  exit 1
fi

# IDEMPOTENCY — see the identical note on Step 4 (ORACLE.md) above. This file
# is EXPLICITLY documented as append-only and tamper-evident (its own header:
# "This log is append-only. Entries are never edited or deleted."). Blind
# regeneration directly violates that invariant, and is the single most
# severe instance of this bug class — it silently discarded real audit
# history, not just placeholder scaffolding.
if [[ -f "$AUDIT_DEST" ]]; then
  log_info "AUDIT_LOG.md already exists at $AUDIT_DEST — leaving it untouched (append-only, never regenerated)."
elif [[ "$DRY_RUN" == false ]]; then
  sed \
    -e "s/{{PROJECT_NAME}}/$ESC_PROJECT/g" \
    -e "s/{{SYNDICATE_VERSION}}/$SYNDICATE_VERSION/g" \
    -e "s/{{HYDRATION_DATE}}/$HYDRATION_DATE/g" \
    "$AUDIT_TEMPLATE" > "$AUDIT_DEST"
  log_ok "Initialized AUDIT_LOG.md → $AUDIT_DEST"
else
  dry_run_echo "sed [template substitution] '$AUDIT_TEMPLATE' → '$AUDIT_DEST'"
fi

# -----------------------------------------------------------------------------
# Step 6: Write .syndicate/config.json (project-local metadata)
# -----------------------------------------------------------------------------
log_section "Step 6: Writing Project Config"

CONFIG_DEST="$STUB_DIR/config.json"

if [[ "$DRY_RUN" == false ]]; then
  cat > "$CONFIG_DEST" <<EOF
{
  "project_name": "$PROJECT_NAME",
  "operator": "$OPERATOR",
  "syndicate_version": "$SYNDICATE_VERSION",
  "hydration_date": "$HYDRATION_DATE",
  "hydration_timestamp": "$HYDRATION_TIMESTAMP",
  "integration_mode": "$MODE",
  "active_shim": "${SHIM}.shim.json",
  "paths": {
    "oracle": ".syndicate/ORACLE.md",
    "test_doctrine": ".syndicate/TEST_DOCTRINE.md",
    "project_map": ".syndicate/project-map.json",
    "audit_log": ".syndicate/logs/AUDIT_LOG.md",
    "routing": ".syndicate/routing.json",
    "core": ".syndicate/core"
  },
  "script_version": "$SCRIPT_VERSION"
}
EOF
  log_ok "Wrote config.json → $CONFIG_DEST"
else
  dry_run_echo "Write config.json → $CONFIG_DEST"
fi

# -----------------------------------------------------------------------------
# Step 7: Update local deployment registry (gitignored — never touches manifest.json)
# -----------------------------------------------------------------------------
log_section "Step 7: Registering Deployment in Local Registry"

REGISTRY_PATH="$CORE_PATH/deployments.local.json"

if [[ "$DRY_RUN" == false ]]; then
  # Create the local registry if it does not exist yet
  if [[ ! -f "$REGISTRY_PATH" ]]; then
    cat > "$REGISTRY_PATH" <<'EOF'
{"description": "Local deployment registry — gitignored. Populated by syndicate-init.sh at hydration time.", "entries": []}
EOF
  fi

  # Build new entry
  NEW_ENTRY=$(jq -n \
    --arg project "$PROJECT_NAME" \
    --arg operator "$OPERATOR" \
    --arg version "$SYNDICATE_VERSION" \
    --arg date "$HYDRATION_DATE" \
    --arg ts "$HYDRATION_TIMESTAMP" \
    --arg shim "${SHIM}.shim.json" \
    --arg mode "$MODE" \
    --arg path "$PROJECT_DIR" \
    '{
      project: $project,
      operator: $operator,
      syndicate_version: $version,
      hydration_date: $date,
      hydration_timestamp: $ts,
      shim_used: $shim,
      integration_mode: $mode,
      project_path: $path
    }')

  # Append to the local registry
  UPDATED_REGISTRY="$(jq \
    --argjson new_entry "$NEW_ENTRY" \
    '.entries += [$new_entry]' \
    "$REGISTRY_PATH")"

  echo "$UPDATED_REGISTRY" > "$REGISTRY_PATH"
  log_ok "Registered deployment in $REGISTRY_PATH"
else
  dry_run_echo "Update entries in $REGISTRY_PATH"
fi

# -----------------------------------------------------------------------------
# Step 8: Update .gitignore for the active governance mode
# -----------------------------------------------------------------------------
log_section "Step 8: Updating .gitignore"

GITIGNORE="$PROJECT_DIR/.gitignore"

if [[ "$GOVERNANCE" == "central" ]]; then
  GITIGNORE_BLOCK="
# The Shim Syndicate — governance is tracked centrally in the syndicate-projects
# repo and symlinked in as .syndicate. Never commit it into this code repo.
.syndicate
"
else
  GITIGNORE_BLOCK="
# The Shim Syndicate — ignore core symlink/subtree re-creation artifacts
.syndicate/core/.git
# Keep the rest of .syndicate tracked (ORACLE, AUDIT_LOG, routing config are project assets)
"
fi

if [[ "$DRY_RUN" == false ]]; then
  if [[ -f "$GITIGNORE" ]]; then
    if grep -q "The Shim Syndicate" "$GITIGNORE"; then
      log_info ".gitignore already contains Syndicate entries. Skipping."
    else
      echo "$GITIGNORE_BLOCK" >> "$GITIGNORE"
      log_ok "Appended Syndicate entries to .gitignore"
    fi
  else
    echo "$GITIGNORE_BLOCK" > "$GITIGNORE"
    log_ok "Created .gitignore with Syndicate entries"
  fi
else
  dry_run_echo "Append Syndicate block to $GITIGNORE"
fi

# -----------------------------------------------------------------------------
# Step 8.5: Wire Gavel git hooks (core.hooksPath) — runs in BOTH modes
# -----------------------------------------------------------------------------
# Point the repo's core.hooksPath at the Core's shared hooks dir so the Gavel
# pre-commit (branch guard) and commit-msg (audit-trace trailer) hooks are
# active and cannot be skipped by downstream repos. This applies to both
# project mode and mission mode (the mission block re-affirms it in Step 13).
log_section "Step 8.5: Wiring Gavel Git Hooks (core.hooksPath)"

if [[ ! -d "$CORE_PATH/hooks" ]]; then
  log_warn "Core hooks directory not found at $CORE_PATH/hooks — commits will NOT be gated."
else
  exec_or_dry "git -C '$PROJECT_DIR' config core.hooksPath '$CORE_PATH/hooks'"
  [[ "$DRY_RUN" == true ]] || log_ok "Wired git hooks → $CORE_PATH/hooks (core.hooksPath)"
  log_info "core.hooksPath is local git config — re-run init or syndicate-adopt.sh after a fresh clone."
fi

# -----------------------------------------------------------------------------
# Step 9: Stage governance changes in the code repo (and, in central mode,
# commit the new project's governance data in the central repo directly —
# there is no code-repo commit that would trigger a sync hook for this
# one-time registration, so it is committed here explicitly).
# -----------------------------------------------------------------------------
if [[ "$GOVERNANCE" == "central" ]]; then
  log_section "Step 9: Staging .gitignore (colocated); committing new project in central repo"

  if [[ "$DRY_RUN" == false ]]; then
    git add "$GITIGNORE" 2>/dev/null || true
    log_ok "Staged .gitignore (governance data lives outside this repo — nothing else to stage)"
    log_info "Run 'git commit -m \"chore: hydrate Shim Syndicate v${SYNDICATE_VERSION} (central governance)\"' to commit."
  else
    dry_run_echo "git add $GITIGNORE"
  fi

  # Register in the central repo's README and commit — one-time, at project
  # hydration. Idempotent: skips if already registered. Uses CENTRAL_REPO_ROOT
  # (the resolved repo), not the raw SYNDICATE_PROJECTS_PATH env var.
  CENTRAL_README="$CENTRAL_REPO_ROOT/README.md"
  if [[ -f "$CENTRAL_README" ]] && grep -q "| $PROJECT_NAME |" "$CENTRAL_README" 2>/dev/null; then
    log_info "$PROJECT_NAME already registered in $CENTRAL_README — skipping."
  elif [[ "$DRY_RUN" == false ]]; then
    if [[ -f "$CENTRAL_README" ]] && grep -q "^| Project | Code repo | Notes |$" "$CENTRAL_README"; then
      NEW_ROW="| $PROJECT_NAME | *(register the code repo manually)* | Hydrated $HYDRATION_DATE |"
      # Insert after the table header separator line (the "|---|---|---|" row
      # immediately following the header) rather than blindly appending, so the
      # table stays well-formed even if there is trailing content after it.
      awk -v newrow="$NEW_ROW" '
        { print }
        /^\| Project \| Code repo \| Notes \|$/ { getline sep; print sep; print newrow; next }
      ' "$CENTRAL_README" > "$CENTRAL_README.tmp" && mv "$CENTRAL_README.tmp" "$CENTRAL_README"
      log_ok "Registered $PROJECT_NAME in $CENTRAL_README"
    else
      log_warn "Could not find a Projects table in $CENTRAL_README — register $PROJECT_NAME manually."
    fi

    (
      cd "$CENTRAL_REPO_ROOT" && \
      git add "$PROJECT_NAME/" README.md 2>/dev/null && \
      git commit -m "feat(${PROJECT_NAME}): hydrate governance (central mode, Syndicate v${SYNDICATE_VERSION})" >/dev/null 2>&1 \
        && log_ok "Committed $PROJECT_NAME governance in $CENTRAL_REPO_ROOT" \
        || log_warn "Nothing to commit in $CENTRAL_REPO_ROOT (or commit failed) — check manually."
    )
  else
    dry_run_echo "Register $PROJECT_NAME in $CENTRAL_README and commit in $CENTRAL_REPO_ROOT"
  fi
else
  log_section "Step 9: Staging .syndicate/ for Initial Commit"

  if [[ "$DRY_RUN" == false ]]; then
    git add "$STUB_DIR/" "$GITIGNORE" 2>/dev/null || true
    log_ok "Staged .syndicate/ and .gitignore"
    log_info "Run 'git commit -m \"chore: hydrate Shim Syndicate v${SYNDICATE_VERSION}\"' to commit."
  else
    dry_run_echo "git add $STUB_DIR/ $GITIGNORE"
  fi
fi

# -----------------------------------------------------------------------------
# MISSION MODE — Steps 10–13 (only when --mission is passed)
# -----------------------------------------------------------------------------
if [[ "$MISSION_MODE" == true ]]; then

  # --------------------------------------------------------------------------
  # Step 10: Verify mission/ branch
  # --------------------------------------------------------------------------
  log_section "Step 10: Mission Branch Verification"

  CURRENT_BRANCH="$(git -C "$PROJECT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "UNKNOWN")"

  if [[ "$CURRENT_BRANCH" != mission/* ]]; then
    log_error "Mission Mode requires a 'mission/' branch. Current branch: $CURRENT_BRANCH"
    log_error "Create a mission branch first:  git checkout -b mission/<name>"
    exit 1
  fi

  MISSION_NAME="${CURRENT_BRANCH#mission/}"
  ESC_MISSION="$(sed_escape "$MISSION_NAME")"
  # Vault directory name: replace any remaining / with - for filesystem safety
  VAULT_DIRNAME="${CURRENT_BRANCH//\//-}"
  VAULT_DIR="$STUB_DIR/vault/${VAULT_DIRNAME}"

  log_ok "Mission branch confirmed: $CURRENT_BRANCH"
  log_ok "Mission name: $MISSION_NAME"
  log_ok "Vault path: $VAULT_DIR"

  # --------------------------------------------------------------------------
  # Step 11: Create branch-isolated vault
  # --------------------------------------------------------------------------
  log_section "Step 11: Creating Mission Vault — $VAULT_DIRNAME"

  exec_or_dry "mkdir -p '$VAULT_DIR'"
  exec_or_dry "mkdir -p '$VAULT_DIR/logs'"

  log_ok "Vault directory created: $VAULT_DIR"

  # --------------------------------------------------------------------------
  # Step 12: Generate Mission Brief, ORACLE.md, and project-map.json in vault
  # --------------------------------------------------------------------------
  log_section "Step 12: Generating Mission Artifacts"

  MISSION_DATE="$(date -u +%Y-%m-%d)"
  MISSION_BRIEF_TEMPLATE="$CORE_PATH/templates/MISSION_BRIEF.md"
  ORACLE_TEMPLATE="$CORE_PATH/templates/ORACLE.md"
  MAP_TEMPLATE="$CORE_PATH/templates/project-map.json"

  # Mission Brief
  # IDEMPOTENCY (see Step 4's note above — same bug class, same fix): re-running
  # `--mission` on an ALREADY-active mission branch (a legitimate, common
  # action — e.g. resuming a session) must never wipe an operator-filled
  # MISSION_BRIEF.md/ORACLE.md/etc. Every generation block below now skips if
  # its destination file already exists.
  if [[ -f "$MISSION_BRIEF_TEMPLATE" ]]; then
    BRIEF_DEST="$VAULT_DIR/MISSION_BRIEF.md"
    if [[ -f "$BRIEF_DEST" ]]; then
      log_info "MISSION_BRIEF.md already exists at $BRIEF_DEST — leaving it untouched."
    elif [[ "$DRY_RUN" == false ]]; then
      sed \
        -e "s/{{MISSION_NAME}}/$ESC_MISSION/g" \
        -e "s/{{MISSION_DATE}}/$MISSION_DATE/g" \
        -e "s/{{OPERATOR_NAME}}/$ESC_OPERATOR/g" \
        -e "s/{{SYNDICATE_VERSION}}/$SYNDICATE_VERSION/g" \
        -e "s/{{PROJECT_NAME}}/$ESC_PROJECT/g" \
        "$MISSION_BRIEF_TEMPLATE" > "$BRIEF_DEST"
      log_ok "Mission Brief generated → $BRIEF_DEST"
    else
      dry_run_echo "sed [template substitution] '$MISSION_BRIEF_TEMPLATE' → '$BRIEF_DEST'"
    fi
  else
    log_warn "MISSION_BRIEF.md template not found at $MISSION_BRIEF_TEMPLATE — skipping."
  fi

  # Mission-local ORACLE.md (inherits from project template)
  VAULT_ORACLE="$VAULT_DIR/ORACLE.md"
  if [[ -f "$VAULT_ORACLE" ]]; then
    log_info "Mission ORACLE.md already exists at $VAULT_ORACLE — leaving it untouched."
  elif [[ -f "$ORACLE_TEMPLATE" ]]; then
    if [[ "$DRY_RUN" == false ]]; then
      sed \
        -e "s/{{PROJECT_NAME}}/$ESC_PROJECT — mission\/$ESC_MISSION/g" \
        -e "s/{{SYNDICATE_VERSION}}/$SYNDICATE_VERSION/g" \
        -e "s/{{HYDRATION_DATE}}/$MISSION_DATE/g" \
        -e "s/{{SHIM_FILE}}/${SHIM}.shim.json/g" \
        -e "s/{{OPERATOR_NAME}}/$ESC_OPERATOR/g" \
        "$ORACLE_TEMPLATE" > "$VAULT_ORACLE"
      log_ok "Mission ORACLE.md generated → $VAULT_ORACLE"
    else
      dry_run_echo "sed [template substitution] '$ORACLE_TEMPLATE' → '$VAULT_ORACLE'"
    fi
  else
    log_warn "ORACLE.md template not found — mission ORACLE.md will be empty."
    exec_or_dry "touch '$VAULT_ORACLE'"
  fi

  # project-map.json
  VAULT_MAP="$VAULT_DIR/project-map.json"
  if [[ -f "$VAULT_MAP" ]]; then
    log_info "Mission project-map.json already exists at $VAULT_MAP — leaving it untouched."
  elif [[ -f "$MAP_TEMPLATE" ]]; then
    if [[ "$DRY_RUN" == false ]]; then
      sed \
        -e "s/{{MISSION_NAME}}/$ESC_MISSION/g" \
        -e "s/{{MISSION_DATE}}/$MISSION_DATE/g" \
        -e "s/{{SYNDICATE_VERSION}}/$SYNDICATE_VERSION/g" \
        -e "s/{{PROJECT_NAME}}/$ESC_PROJECT/g" \
        "$MAP_TEMPLATE" > "$VAULT_MAP"
      log_ok "project-map.json generated → $VAULT_MAP"
    else
      dry_run_echo "sed [template substitution] '$MAP_TEMPLATE' → '$VAULT_MAP'"
    fi
  else
    log_warn "project-map.json template not found — skipping."
  fi

  # RESERVATIONS.json for this mission (file-ownership reservation ledger)
  RESERVATIONS_TEMPLATE="$CORE_PATH/templates/RESERVATIONS.json"
  VAULT_RESERVATIONS="$VAULT_DIR/RESERVATIONS.json"
  if [[ -f "$VAULT_RESERVATIONS" ]]; then
    log_info "RESERVATIONS.json already exists at $VAULT_RESERVATIONS — leaving it untouched (it holds live agent locks)."
  elif [[ -f "$RESERVATIONS_TEMPLATE" ]]; then
    if [[ "$DRY_RUN" == false ]]; then
      sed \
        -e "s/{{project_name}}/$ESC_PROJECT/g" \
        "$RESERVATIONS_TEMPLATE" > "$VAULT_RESERVATIONS"
      log_ok "RESERVATIONS.json generated → $VAULT_RESERVATIONS"
    else
      dry_run_echo "sed [template substitution] '$RESERVATIONS_TEMPLATE' → '$VAULT_RESERVATIONS'"
    fi
  else
    log_warn "RESERVATIONS.json template not found — skipping."
  fi

  # TEST_DOCTRINE.md for this mission (inherits from project template)
  VAULT_DOCTRINE="$VAULT_DIR/TEST_DOCTRINE.md"
  if [[ -f "$VAULT_DOCTRINE" ]]; then
    log_info "Mission TEST_DOCTRINE.md already exists at $VAULT_DOCTRINE — leaving it untouched."
  elif [[ -f "$DOCTRINE_TEMPLATE" ]]; then
    if [[ "$DRY_RUN" == false ]]; then
      sed \
        -e "s/{{PROJECT_NAME}}/$ESC_PROJECT — mission\/$ESC_MISSION/g" \
        -e "s/{{SYNDICATE_VERSION}}/$SYNDICATE_VERSION/g" \
        -e "s/{{HYDRATION_DATE}}/$MISSION_DATE/g" \
        -e "s/{{OPERATOR_NAME}}/$ESC_OPERATOR/g" \
        "$DOCTRINE_TEMPLATE" > "$VAULT_DOCTRINE"
      log_ok "Mission TEST_DOCTRINE.md generated → $VAULT_DOCTRINE"
    else
      dry_run_echo "sed [template substitution] '$DOCTRINE_TEMPLATE' → '$VAULT_DOCTRINE'"
    fi
  else
    log_warn "TEST_DOCTRINE.md template not found — mission doctrine will be absent."
  fi

  # AUDIT_LOG.md for this mission
  VAULT_AUDIT="$VAULT_DIR/logs/AUDIT_LOG.md"
  AUDIT_TEMPLATE="$CORE_PATH/templates/AUDIT_LOG.md"
  if [[ -f "$VAULT_AUDIT" ]]; then
    # Same append-only invariant as the project-level AUDIT_LOG.md (Step 5) —
    # never regenerate over real entries.
    log_info "Mission AUDIT_LOG.md already exists at $VAULT_AUDIT — leaving it untouched (append-only)."
  elif [[ -f "$AUDIT_TEMPLATE" ]]; then
    if [[ "$DRY_RUN" == false ]]; then
      sed \
        -e "s/{{PROJECT_NAME}}/$ESC_PROJECT — mission\/$ESC_MISSION/g" \
        -e "s/{{SYNDICATE_VERSION}}/$SYNDICATE_VERSION/g" \
        -e "s/{{HYDRATION_DATE}}/$MISSION_DATE/g" \
        "$AUDIT_TEMPLATE" > "$VAULT_AUDIT"
      log_ok "Mission AUDIT_LOG.md initialized → $VAULT_AUDIT"
    else
      dry_run_echo "sed [template substitution] '$AUDIT_TEMPLATE' → '$VAULT_AUDIT'"
    fi
  fi

  # --------------------------------------------------------------------------
  # Step 13: Confirm Gavel git hooks are wired (core.hooksPath)
  # --------------------------------------------------------------------------
  # Hooks are wired via core.hooksPath in the common flow (Step 8.5) so they
  # apply in both project and mission mode, survive branch switches, and cannot
  # be skipped. Re-affirm the wiring here and warn loudly if the Core hooks are
  # missing.
  log_section "Step 13: Confirming Gavel Git Hooks"

  if [[ -f "$CORE_PATH/hooks/pre-commit" && -f "$CORE_PATH/hooks/commit-msg" ]]; then
    exec_or_dry "git -C '$PROJECT_DIR' config core.hooksPath '$CORE_PATH/hooks'"
    if [[ "$DRY_RUN" != true ]]; then
      log_ok "Gavel hooks active via core.hooksPath → $CORE_PATH/hooks"
      log_ok "All commits on this repo will now pass through The Gavel (pre-commit + commit-msg)."
    fi
  else
    log_warn "Core hooks missing at $CORE_PATH/hooks (pre-commit/commit-msg) — commits will NOT be gated."
  fi

  # --------------------------------------------------------------------------
  # Step 13.5: Central mode only — commit the new mission vault directly in
  # the central repo. Every LATER commit on this mission branch triggers
  # hooks/post-commit (and hooks/post-merge on merge) to sync automatically,
  # but this first vault-creation moment has no code-repo commit to hang a
  # hook off yet, so it is committed here explicitly (mirrors Step 9).
  # --------------------------------------------------------------------------
  if [[ "$GOVERNANCE" == "central" ]]; then
    log_section "Step 13.5: Committing Mission Vault in Central Repo"
    if [[ "$DRY_RUN" == false ]]; then
      (
        cd "$CENTRAL_REPO_ROOT" && \
        git add "$PROJECT_NAME/" 2>/dev/null && \
        git commit -m "feat(${PROJECT_NAME}): initialize vault for ${CURRENT_BRANCH}" >/dev/null 2>&1 \
          && log_ok "Committed mission vault in $CENTRAL_REPO_ROOT" \
          || log_warn "Nothing to commit in $CENTRAL_REPO_ROOT (or commit failed) — check manually."
      )
    else
      dry_run_echo "Commit mission vault for $PROJECT_NAME in $CENTRAL_REPO_ROOT"
    fi
  fi

fi  # end MISSION_MODE

# -----------------------------------------------------------------------------
# Done
# -----------------------------------------------------------------------------
log_section "Hydration Complete"
echo ""
echo -e "  ${GREEN}${BOLD}The Shim Syndicate v${SYNDICATE_VERSION} has been deployed to:${RESET}"
echo -e "  ${BOLD}$PROJECT_DIR/.syndicate/${RESET}"
if [[ "$GOVERNANCE" == "central" ]]; then
  echo -e "  ${CYAN}(governance mode: central — .syndicate is a symlink to $STUB_DIR)${RESET}"
  echo -e "  ${CYAN}Governance commits made from mission branches sync to the central repo${RESET}"
  echo -e "  ${CYAN}automatically via hooks/post-commit and hooks/post-merge — no manual step needed.${RESET}"
else
  echo -e "  ${CYAN}(governance mode: colocated — .syndicate is a real directory, tracked in this repo)${RESET}"
fi
echo ""

if [[ "$MISSION_MODE" == true ]]; then
  echo -e "  ${BOLD}Mission Vault:${RESET}  $VAULT_DIR"
  echo -e "  ${BOLD}Branch:${RESET}         $CURRENT_BRANCH"
  echo ""
  echo -e "  ${BOLD}Mission Mode — Next Steps:${RESET}"
  echo ""
  echo -e "  1. ${CYAN}Complete the Mission Brief:${RESET}"
  echo -e "     ${BOLD}$VAULT_DIR/MISSION_BRIEF.md${RESET}"
  echo -e "     Fill in objective, scope, and agent assignments."
  echo ""
  echo -e "  2. ${CYAN}Complete the Mission ORACLE.md:${RESET}"
  echo -e "     ${BOLD}$VAULT_DIR/ORACLE.md${RESET}"
  echo -e "     Fill in all {{placeholder}} values before launching agents."
  echo ""
  echo -e "  2b. ${CYAN}Complete the Mission TEST_DOCTRINE.md:${RESET}"
  echo -e "     ${BOLD}$VAULT_DIR/TEST_DOCTRINE.md${RESET}"
  echo -e "     Fill in §2.2 (axioms), §3.1 (thresholds), §3.2 (mandatory matrix)."
  echo -e "     The Gavel will FAIL commits with unfilled {{placeholder}} tokens."
  echo ""
  echo -e "  3. ${CYAN}Give The Ledger the project-map.json:${RESET}"
  echo -e "     ${BOLD}$VAULT_DIR/project-map.json${RESET}"
  echo -e "     Ask The Ledger to populate the structure, dependencies, and prior_decisions fields."
  echo ""
  echo -e "  4. ${CYAN}Launch the session (auto-loads vault context):${RESET}"
  echo -e "     ${BOLD}bash syndicate-session.sh attach${RESET}"
  echo -e "     tmux windows: [0] mission  [1] lead  [2] ledger  [3] gavel"
  echo ""
  echo -e "  5. ${CYAN}Gavel hooks are active — all commits are gated:${RESET}"
  echo -e "     pre-commit : branch guard + oracle check + secrets scan"
  echo -e "     commit-msg : Syndicate-Audit-Trace trailer required"
  echo ""
  if [[ "$GOVERNANCE" == "central" ]]; then
    echo -e "  6. ${CYAN}Vault scaffold already committed centrally${RESET} (Step 13.5) — nothing to do here."
    echo -e "     Future commits on this branch sync to the central repo automatically."
  else
    echo -e "  6. ${CYAN}Commit the vault scaffold (mission context tracked):${RESET}"
    echo -e "     ${BOLD}git add .syndicate/vault/ && git commit -m \"chore: initialize vault for $CURRENT_BRANCH"
    echo -e "     Syndicate-Audit-Trace: @gavel PASS — $(date -u +%Y-%m-%dT%H:%M:%SZ)\"${RESET}"
  fi
  echo ""
else
  echo -e "  ${BOLD}Next Steps:${RESET}"
  echo ""
  echo -e "  1. ${CYAN}Complete the ORACLE.md:${RESET}"
  echo -e "     Open ${BOLD}.syndicate/ORACLE.md${RESET} and fill in all {{placeholder}} values."
  echo -e "     The Lead will refuse to operate without a complete Oracle."
  echo ""
  echo -e "  1b. ${CYAN}Complete the TEST_DOCTRINE.md:${RESET}"
  echo -e "     Open ${BOLD}.syndicate/TEST_DOCTRINE.md${RESET} and fill in:"
  echo -e "     §2.2 PROJECT_COMPOSABILITY_AXIOMS, §3.1 COVERAGE_THRESHOLDS, §3.2 MANDATORY_TEST_MATRIX"
  echo -e "     The Gavel will FAIL commits with unfilled {{placeholder}} tokens."
  echo ""
  echo -e "  1c. ${CYAN}Give The Ledger the project-map.json:${RESET}"
  echo -e "     Open ${BOLD}.syndicate/project-map.json${RESET} and ask The Ledger to populate"
  echo -e "     structure, dependencies, and prior_decisions."
  echo ""
  echo -e "  2. ${CYAN}Start the session:${RESET}"
  echo -e "     ${BOLD}bash syndicate-session.sh attach${RESET}"
  echo -e "     tmux windows: [0] mission  [1] lead  [2] ledger  [3] gavel"
  echo ""
  echo -e "  3. ${CYAN}Initialize a mission branch when ready to build:${RESET}"
  echo -e "     ${BOLD}git checkout -b mission/<name>${RESET}"
  echo -e "     ${BOLD}bash syndicate-init.sh --mission${RESET}"
  echo ""
  if [[ "$GOVERNANCE" == "central" ]]; then
    echo -e "  4. ${CYAN}Commit .gitignore (governance itself is already committed centrally):${RESET}"
    echo -e "     ${BOLD}git commit -m \"chore: hydrate Shim Syndicate v${SYNDICATE_VERSION} (central governance)\"${RESET}"
  else
    echo -e "  4. ${CYAN}Commit the .syndicate/ directory:${RESET}"
    echo -e "     ${BOLD}git commit -m \"chore: hydrate Shim Syndicate v${SYNDICATE_VERSION}\"${RESET}"
  fi
  echo ""
fi

echo -e "  ${YELLOW}The Ledger, The Lead, and The Gavel are ready for deployment.${RESET}"
echo ""
