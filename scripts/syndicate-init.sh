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
#   generates a project-specific ORACLE.md, and initializes the AUDIT_LOG.md.
#
#   With --mission: Operates in Mission Mode. Verifies the current branch is a
#   mission/ branch, creates a branch-isolated vault at
#   .syndicate/vault/<branch-name>/, generates a Mission Brief, copies the
#   ORACLE.md and project-map.json templates into the vault, and installs the
#   Gavel git hooks (pre-commit and commit-msg).
#
# USAGE:
#   cd /path/to/your-project
#   bash /path/to/syndicate-init.sh [OPTIONS]
#
# OPTIONS:
#   --mode      Integration mode: 'symlink' (default) or 'subtree'
#   --shim      Shim config to use: 'claude' (default), 'gemini', or 'local'
#   --operator  Operator name for audit records (quoted string)
#   --project   Project name (defaults to current directory name)
#   --core      Path to the Syndicate Core repo (required if not set via env)
#   --mission   Run in Mission Mode: initialize a branch-specific vault
#   --dry-run   Preview all actions without executing them
#   --help      Show this help message
#
# ENVIRONMENT VARIABLES:
#   SYNDICATE_CORE_PATH     Path to the cloned Syndicate Core repository
#   SYNDICATE_DEFAULT_SHIM  Default shim to use (claude | gemini | local)
#
# EXAMPLES:
#   bash syndicate-init.sh --operator "Jane Smith" --shim claude
#   SYNDICATE_CORE_PATH=~/syndicate bash syndicate-init.sh --mode subtree
#   bash syndicate-init.sh --mission --operator "Jane Smith"
#
# =============================================================================
set -euo pipefail

# -----------------------------------------------------------------------------
# Constants
# -----------------------------------------------------------------------------
SCRIPT_VERSION="2.1.0"
SYNDICATE_DIR=".syndicate"
REQUIRED_COMMANDS=("git" "jq")
OPTIONAL_COMMANDS=("claude" "gemini" "ollama" "opencode")

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
# Default values
# -----------------------------------------------------------------------------
MODE="symlink"
SHIM="claude"
OPERATOR="${SYNDICATE_OPERATOR:-}"
PROJECT_NAME=""
CORE_PATH="${SYNDICATE_CORE_PATH:-}"
DRY_RUN=false
MISSION_MODE=false
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
    --mode)      MODE="$2";         shift 2 ;;
    --shim)      SHIM="$2";         shift 2 ;;
    --operator)  OPERATOR="$2";     shift 2 ;;
    --project)   PROJECT_NAME="$2"; shift 2 ;;
    --core)      CORE_PATH="$2";    shift 2 ;;
    --mission)   MISSION_MODE=true; shift   ;;
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
if [[ "$SHIM" != "claude" && "$SHIM" != "gemini" && "$SHIM" != "local" ]]; then
  log_error "Invalid --shim value: '$SHIM'. Must be 'claude', 'gemini', or 'local'."
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
  read -r -p "  Re-initialize and overwrite? (y/N): " confirm
  if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    log_info "Aborted by user."
    exit 0
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
echo -e "  ${BOLD}Shim:${RESET}             $SHIM"
echo -e "  ${BOLD}Syndicate Version:${RESET} $SYNDICATE_VERSION"
echo -e "  ${BOLD}Operator:${RESET}         $OPERATOR"
echo -e "  ${BOLD}Date:${RESET}             $HYDRATION_DATE"
echo ""

if [[ "$DRY_RUN" == true ]]; then
  log_warn "DRY-RUN MODE — no changes will be made."
fi

read -r -p "Proceed with hydration? (y/N): " confirm
if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
  log_info "Aborted by user."
  exit 0
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
# Step 1: Create .syndicate/ directory structure
# -----------------------------------------------------------------------------
log_section "Step 1: Creating .syndicate/ Directory"

STUB_DIR="$PROJECT_DIR/$SYNDICATE_DIR"

exec_or_dry "mkdir -p '$STUB_DIR'"
exec_or_dry "mkdir -p '$STUB_DIR/identities'"
exec_or_dry "mkdir -p '$STUB_DIR/logs'"

log_ok "Created directory structure: $STUB_DIR"

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
# Step 3.1: Inject Gavel-specific tool permissions
# -----------------------------------------------------------------------------
log_section "Step 3.1: Injecting Gavel-specific Tool Permissions"

if [[ "$DRY_RUN" == false ]]; then
  # Read the current routing.json
  CURRENT_ROUTING_JSON=$(cat "$SHIM_DEST")

  # Use jq to add the --read-only-bash flag to Gavel's cli_flags
  UPDATED_ROUTING_JSON=$(echo "$CURRENT_ROUTING_JSON" | jq '.agents.gavel.backend_config.cli_flags += ["--read-only-bash"]')

  # Write the modified JSON back
  echo "$UPDATED_ROUTING_JSON" > "$SHIM_DEST"
  log_ok "Injected --read-only-bash flag for The Gavel in $SHIM_DEST"
else
  dry_run_echo "jq '.agents.gavel.backend_config.cli_flags += ["--read-only-bash"]' '$SHIM_DEST' > '$SHIM_DEST'"
fi

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

if [[ "$DRY_RUN" == false ]]; then
  sed \
    -e "s/{{PROJECT_NAME}}/$PROJECT_NAME/g" \
    -e "s/{{SYNDICATE_VERSION}}/$SYNDICATE_VERSION/g" \
    -e "s/{{HYDRATION_DATE}}/$HYDRATION_DATE/g" \
    -e "s/{{SHIM_FILE}}/${SHIM}.shim.json/g" \
    -e "s/{{OPERATOR_NAME}}/$OPERATOR/g" \
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
else
  if [[ "$DRY_RUN" == false ]]; then
    sed \
      -e "s/{{PROJECT_NAME}}/$PROJECT_NAME/g" \
      -e "s/{{SYNDICATE_VERSION}}/$SYNDICATE_VERSION/g" \
      -e "s/{{HYDRATION_DATE}}/$HYDRATION_DATE/g" \
      -e "s/{{OPERATOR_NAME}}/$OPERATOR/g" \
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
# Step 5: Initialize AUDIT_LOG.md
# -----------------------------------------------------------------------------
log_section "Step 5: Initializing AUDIT_LOG.md"

AUDIT_TEMPLATE="$CORE_PATH/templates/AUDIT_LOG.md"
AUDIT_DEST="$STUB_DIR/logs/AUDIT_LOG.md"

if [[ ! -f "$AUDIT_TEMPLATE" ]]; then
  log_error "AUDIT_LOG.md template not found at: $AUDIT_TEMPLATE"
  exit 1
fi

if [[ "$DRY_RUN" == false ]]; then
  sed \
    -e "s/{{PROJECT_NAME}}/$PROJECT_NAME/g" \
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
# Step 7: Update Syndicate Core deployment registry
# -----------------------------------------------------------------------------
log_section "Step 7: Registering Deployment in Syndicate Core"

MANIFEST_PATH="$CORE_PATH/manifest.json"

if [[ "$DRY_RUN" == false ]]; then
  # Read existing entries
  EXISTING_REGISTRY="$(jq '.deployment_registry.entries' "$MANIFEST_PATH")"

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

  # Append to manifest
  UPDATED_MANIFEST="$(jq \
    --argjson new_entry "$NEW_ENTRY" \
    '.deployment_registry.entries += [$new_entry]' \
    "$MANIFEST_PATH")"

  echo "$UPDATED_MANIFEST" > "$MANIFEST_PATH"
  log_ok "Registered deployment in $MANIFEST_PATH"
else
  dry_run_echo "Update deployment_registry in $MANIFEST_PATH"
fi

# -----------------------------------------------------------------------------
# Step 8: Add .syndicate to .gitignore (selective)
# -----------------------------------------------------------------------------
log_section "Step 8: Updating .gitignore"

GITIGNORE="$PROJECT_DIR/.gitignore"

GITIGNORE_BLOCK="
# The Shim Syndicate — ignore core symlink/subtree re-creation artifacts
.syndicate/core/.git
# Keep the rest of .syndicate tracked (ORACLE, AUDIT_LOG, routing config are project assets)
"

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
# Step 9: Initial git commit of Syndicate stub
# -----------------------------------------------------------------------------
log_section "Step 9: Staging .syndicate/ for Initial Commit"

if [[ "$DRY_RUN" == false ]]; then
  git add "$STUB_DIR/" "$GITIGNORE" 2>/dev/null || true
  log_ok "Staged .syndicate/ and .gitignore"
  log_info "Run 'git commit -m \"chore: hydrate Shim Syndicate v${SYNDICATE_VERSION}\"' to commit."
else
  dry_run_echo "git add $STUB_DIR/ $GITIGNORE"
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
  if [[ -f "$MISSION_BRIEF_TEMPLATE" ]]; then
    BRIEF_DEST="$VAULT_DIR/MISSION_BRIEF.md"
    if [[ "$DRY_RUN" == false ]]; then
      sed \
        -e "s/{{MISSION_NAME}}/$MISSION_NAME/g" \
        -e "s/{{MISSION_DATE}}/$MISSION_DATE/g" \
        -e "s/{{OPERATOR_NAME}}/$OPERATOR/g" \
        -e "s/{{SYNDICATE_VERSION}}/$SYNDICATE_VERSION/g" \
        -e "s/{{PROJECT_NAME}}/$PROJECT_NAME/g" \
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
  if [[ -f "$ORACLE_TEMPLATE" ]]; then
    if [[ "$DRY_RUN" == false ]]; then
      sed \
        -e "s/{{PROJECT_NAME}}/$PROJECT_NAME — mission\/$MISSION_NAME/g" \
        -e "s/{{SYNDICATE_VERSION}}/$SYNDICATE_VERSION/g" \
        -e "s/{{HYDRATION_DATE}}/$MISSION_DATE/g" \
        -e "s/{{SHIM_FILE}}/${SHIM}.shim.json/g" \
        -e "s/{{OPERATOR_NAME}}/$OPERATOR/g" \
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
  if [[ -f "$MAP_TEMPLATE" ]]; then
    if [[ "$DRY_RUN" == false ]]; then
      sed \
        -e "s/{{MISSION_NAME}}/$MISSION_NAME/g" \
        -e "s/{{MISSION_DATE}}/$MISSION_DATE/g" \
        -e "s/{{SYNDICATE_VERSION}}/$SYNDICATE_VERSION/g" \
        -e "s/{{PROJECT_NAME}}/$PROJECT_NAME/g" \
        "$MAP_TEMPLATE" > "$VAULT_MAP"
      log_ok "project-map.json generated → $VAULT_MAP"
    else
      dry_run_echo "sed [template substitution] '$MAP_TEMPLATE' → '$VAULT_MAP'"
    fi
  else
    log_warn "project-map.json template not found — skipping."
  fi

  # TEST_DOCTRINE.md for this mission (inherits from project template)
  VAULT_DOCTRINE="$VAULT_DIR/TEST_DOCTRINE.md"
  if [[ -f "$DOCTRINE_TEMPLATE" ]]; then
    if [[ "$DRY_RUN" == false ]]; then
      sed \
        -e "s/{{PROJECT_NAME}}/$PROJECT_NAME — mission\/$MISSION_NAME/g" \
        -e "s/{{SYNDICATE_VERSION}}/$SYNDICATE_VERSION/g" \
        -e "s/{{HYDRATION_DATE}}/$MISSION_DATE/g" \
        -e "s/{{OPERATOR_NAME}}/$OPERATOR/g" \
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
  if [[ -f "$AUDIT_TEMPLATE" ]]; then
    if [[ "$DRY_RUN" == false ]]; then
      sed \
        -e "s/{{PROJECT_NAME}}/$PROJECT_NAME — mission\/$MISSION_NAME/g" \
        -e "s/{{SYNDICATE_VERSION}}/$SYNDICATE_VERSION/g" \
        -e "s/{{HYDRATION_DATE}}/$MISSION_DATE/g" \
        "$AUDIT_TEMPLATE" > "$VAULT_AUDIT"
      log_ok "Mission AUDIT_LOG.md initialized → $VAULT_AUDIT"
    else
      dry_run_echo "sed [template substitution] '$AUDIT_TEMPLATE' → '$VAULT_AUDIT'"
    fi
  fi

  # --------------------------------------------------------------------------
  # Step 13: Install Gavel git hooks
  # --------------------------------------------------------------------------
  log_section "Step 13: Installing Gavel Git Hooks"

  GIT_HOOKS_DIR="$PROJECT_DIR/.git/hooks"
  HOOK_SOURCE_DIR="$CORE_PATH/hooks"

  if [[ ! -d "$GIT_HOOKS_DIR" ]]; then
    log_error ".git/hooks directory not found at $GIT_HOOKS_DIR"
    log_error "Ensure this is a valid git repository."
    exit 1
  fi

  for hook in pre-commit commit-msg; do
    HOOK_SRC="$HOOK_SOURCE_DIR/$hook"
    HOOK_DEST="$GIT_HOOKS_DIR/$hook"

    if [[ ! -f "$HOOK_SRC" ]]; then
      log_warn "Hook source not found: $HOOK_SRC — skipping $hook"
      continue
    fi

    if [[ -f "$HOOK_DEST" ]] && [[ "$DRY_RUN" == false ]]; then
      log_warn "Existing $hook hook found at $HOOK_DEST — backing up to ${HOOK_DEST}.bak"
      cp "$HOOK_DEST" "${HOOK_DEST}.bak"
    fi

    exec_or_dry "cp '$HOOK_SRC' '$HOOK_DEST'"
    exec_or_dry "chmod +x '$HOOK_DEST'"
    log_ok "Installed: $HOOK_DEST"
  done

  log_ok "Gavel hooks active. All commits on this repo will now pass through The Gavel."

fi  # end MISSION_MODE

# -----------------------------------------------------------------------------
# Done
# -----------------------------------------------------------------------------
log_section "Hydration Complete"
echo ""
echo -e "  ${GREEN}${BOLD}The Shim Syndicate v${SYNDICATE_VERSION} has been deployed to:${RESET}"
echo -e "  ${BOLD}$PROJECT_DIR/.syndicate/${RESET}"
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
  echo -e "  6. ${CYAN}Commit the vault scaffold (mission context tracked):${RESET}"
  echo -e "     ${BOLD}git add .syndicate/vault/ && git commit -m \"chore: initialize vault for $CURRENT_BRANCH"
  echo -e "     Syndicate-Audit-Trace: @gavel PASS — $(date -u +%Y-%m-%dT%H:%M:%SZ)\"${RESET}"
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
  echo -e "  2. ${CYAN}Start the session:${RESET}"
  echo -e "     ${BOLD}bash syndicate-session.sh attach${RESET}"
  echo -e "     tmux windows: [0] mission  [1] lead  [2] ledger  [3] gavel"
  echo ""
  echo -e "  3. ${CYAN}Initialize a mission branch when ready to build:${RESET}"
  echo -e "     ${BOLD}git checkout -b mission/<name>${RESET}"
  echo -e "     ${BOLD}bash syndicate-init.sh --mission${RESET}"
  echo ""
  echo -e "  4. ${CYAN}Commit the .syndicate/ directory:${RESET}"
  echo -e "     ${BOLD}git commit -m \"chore: hydrate Shim Syndicate v${SYNDICATE_VERSION}\"${RESET}"
  echo ""
fi

echo -e "  ${YELLOW}The Ledger, The Lead, and The Gavel are ready for deployment.${RESET}"
echo ""
