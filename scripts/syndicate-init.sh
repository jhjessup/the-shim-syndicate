#!/usr/bin/env bash
# =============================================================================
# syndicate-init.sh — The Shim Syndicate Project Hydration Script
# =============================================================================
# Version: 1.0.0
# Repository: jhjessup/the-shim-syndicate
#
# DESCRIPTION:
#   Hydrates a new or existing project repository with The Shim Syndicate
#   agent team. Creates a local .syndicate/ stub, links the Syndicate Core,
#   generates a project-specific ORACLE.md, and initializes the AUDIT_LOG.md.
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
#   --dry-run   Preview all actions without executing them
#   --help      Show this help message
#
# ENVIRONMENT VARIABLES:
#   SYNDICATE_CORE_PATH   Path to the cloned Syndicate Core repository
#   SYNDICATE_DEFAULT_SHIM  Default shim to use (claude | gemini | local)
#
# EXAMPLES:
#   bash syndicate-init.sh --operator "Jane Smith" --shim claude
#   SYNDICATE_CORE_PATH=~/syndicate bash syndicate-init.sh --mode subtree
#
# =============================================================================
set -euo pipefail

# -----------------------------------------------------------------------------
# Constants
# -----------------------------------------------------------------------------
SCRIPT_VERSION="1.0.0"
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
    --mode)      MODE="$2";       shift 2 ;;
    --shim)      SHIM="$2";       shift 2 ;;
    --operator)  OPERATOR="$2";   shift 2 ;;
    --project)   PROJECT_NAME="$2"; shift 2 ;;
    --core)      CORE_PATH="$2";  shift 2 ;;
    --dry-run)   DRY_RUN=true;    shift   ;;
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
# Done
# -----------------------------------------------------------------------------
log_section "Hydration Complete"
echo ""
echo -e "  ${GREEN}${BOLD}The Shim Syndicate v${SYNDICATE_VERSION} has been deployed to:${RESET}"
echo -e "  ${BOLD}$PROJECT_DIR/.syndicate/${RESET}"
echo ""
echo -e "  ${BOLD}Next Steps:${RESET}"
echo -e "  1. ${CYAN}Complete the ORACLE.md:${RESET}"
echo -e "     Open ${BOLD}.syndicate/ORACLE.md${RESET} and fill in all {{placeholder}} values."
echo -e "     The Lead will refuse to operate without a complete Oracle."
echo ""
echo -e "  2. ${CYAN}Start The Lead:${RESET}"
echo -e "     Load ${BOLD}.syndicate/core/identities/THE_LEAD.md${RESET} as your system prompt in Claude."
echo -e "     Point it to ${BOLD}.syndicate/ORACLE.md${RESET} and ${BOLD}.syndicate/logs/AUDIT_LOG.md${RESET}."
echo ""
echo -e "  3. ${CYAN}Invoke The Ledger for context:${RESET}"
echo -e "     Use ${BOLD}.syndicate/core/identities/THE_LEDGER.md${RESET} as the Gemini system prompt."
echo -e "     Provide it the full project codebase or relevant context windows."
echo ""
echo -e "  4. ${CYAN}Run The Gavel after each implementation session:${RESET}"
echo -e "     Load ${BOLD}.syndicate/core/identities/THE_GAVEL.md${RESET} in your local model / OpenCode."
echo -e "     Direct it to audit the changed files and append findings to AUDIT_LOG.md."
echo ""
echo -e "  5. ${CYAN}Commit the .syndicate/ directory:${RESET}"
echo -e "     ${BOLD}git commit -m \"chore: hydrate Shim Syndicate v${SYNDICATE_VERSION}\"${RESET}"
echo ""
echo -e "  ${YELLOW}The Ledger, The Lead, and The Gavel are ready for deployment.${RESET}"
echo ""
