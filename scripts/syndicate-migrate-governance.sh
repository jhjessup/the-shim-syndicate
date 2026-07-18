#!/usr/bin/env bash
# =============================================================================
# syndicate-migrate-governance.sh — The Shim Syndicate Governance Migration Script
# =============================================================================
# Version: 1.0.0
# Repository: jhjessup/the-shim-syndicate
#
# DESCRIPTION:
#   Migrates an existing project's co-located .syndicate/ directory (a real,
#   git-tracked directory inside the project's own repo) to the centralized
#   syndicate-projects pattern, where governance lives externally and the
#   project root gets a .syndicate symlink pointing to the central location.
#
#   This script automates a manual migration procedure that was previously
#   performed by hand for the mcp-gateway project. It is designed to be safe
#   to run on a real, working project — it moves real files, rewrites git
#   tracking state, and verifies zero data loss via SHA-256 hash comparison.
#
# USAGE:
#   bash syndicate-migrate-governance.sh [PROJECT_DIR] [OPTIONS]
#
# ARGUMENTS:
#   PROJECT_DIR   Path to the project to migrate (default: current directory)
#
# OPTIONS:
#   --dry-run             Preview all actions without executing them — MUST
#                          actually preview what WOULD be moved/hashed/committed.
#   --syndicate-projects  Override the central repo path (default:
#                          $SYNDICATE_PROJECTS_PATH env var, or $HOME/syndicate-projects)
#   --project             Override the project name used for the central
#                          directory (default: basename of PROJECT_DIR)
#   --help, -h            Show help
#
# PRE-FLIGHT CHECKS (fail loudly and exit 1, do not proceed, if any of these
# are true):
#   - PROJECT_DIR is not a git repository
#   - PROJECT_DIR/.syndicate does not exist, or is already a symlink
#     (nothing to migrate — this script is for co-located -> central migration only)
#   - The resolved central path (SYNDICATE_PROJECTS_PATH or --syndicate-projects)
#     does not exist, or is not a git repository
#   - A directory already exists at $SYNDICATE_PROJECTS_PATH/$PROJECT_NAME
#     (refuse to overwrite an existing central project — this is a one-shot
#     migration tool, not a merge tool)
#
# STEPS (automated from the manual procedure):
#   1. Snapshot SHA-256 hash of every file in .syndicate/ BEFORE moving anything
#   2. Remove .syndicate from the project's git index (git rm -r --cached .syndicate)
#   3. Move .syndicate/ to $SYNDICATE_PROJECTS_PATH/$PROJECT_NAME
#   4. If an empty, stray identities/ directory exists inside the moved directory
#      (a leftover artifact from an older hydration script version), remove it
#      — it is not part of the current central layout and would not match other
#      centrally-governed projects. Use rmdir (not rm -rf) so this only ever
#      removes it if it is genuinely empty — never destroy content by mistake.
#   5. Re-verify zero data loss with a full hash comparison against the Step 1
#      snapshot — every file that existed before the move must exist at the new
#      location with an IDENTICAL hash (except the removed-if-empty identities/
#      dir, which by definition had no files to lose). If ANY hash differs or
#      any file is missing, the script must STOP with a clear error and NOT
#      proceed to any further step — do not silently continue.
#   6. Create the symlink: ln -s "$SYNDICATE_PROJECTS_PATH/$PROJECT_NAME" "$PROJECT_DIR/.syndicate"
#   7. Update the project's .gitignore: if it currently has the OLD colocated
#      Syndicate block (a comment containing "The Shim Syndicate" followed by
#      ".syndicate/core/.git" — i.e. a PARTIAL ignore, not a full ignore),
#      REPLACE that block with the new central-mode block (a single ".syndicate"
#      line, full ignore). Do not just skip if a Syndicate block already exists
#      (the existing syndicate-init.sh's own gitignore logic does that check and
#      it is WRONG for a migration scenario — the migration must actively
#      replace stale colocated-style gitignore content, not leave it in place
#      alongside the new symlink, which would leave governance trackable again
#      in some git configurations).
#   8. Register the project in $SYNDICATE_PROJECTS_PATH/README.md's Projects
#      table (idempotent — skip if a row for this project already exists).
#   9. Commit the new directory + README change in $SYNDICATE_PROJECTS_PATH
#      (the central repo) — do NOT touch or commit any OTHER project's
#      pre-existing uncommitted changes that might exist in that repo (check
#      git status first and only git add this project's own new directory
#      plus README.md, never a blind git add -A).
#  10. Stage the .gitignore change in the project's own repo (git add
#      .gitignore) — but do NOT commit in the project's repo (that's the
#      operator's call, same as the existing syndicate-init.sh's Step 9
#      behavior for the initial hydration commit message).
#
# EXAMPLES:
#   cd /path/to/my-project && bash /path/to/syndicate-migrate-governance.sh
#   bash syndicate-migrate-governance.sh /path/to/my-project --dry-run
#   bash syndicate-migrate-governance.sh --syndicate-projects /custom/path --project my-project
#
# =============================================================================
set -euo pipefail

# -----------------------------------------------------------------------------
# Constants
# -----------------------------------------------------------------------------
SCRIPT_VERSION="1.0.0"
SYNDICATE_DIR=".syndicate"
SYNDICATE_PROJECTS_PATH="${SYNDICATE_PROJECTS_PATH:-$HOME/syndicate-projects}"

# ANSI color codes (matching syndicate-init.sh style)
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# -----------------------------------------------------------------------------
# Logging helpers (verbatim from syndicate-init.sh)
# -----------------------------------------------------------------------------
log_info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
log_ok()      { echo -e "${GREEN}[OK]${RESET}    $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
log_error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; }
log_section() { echo -e "\n${BOLD}── $* ──${RESET}"; }
dry_run_echo(){ echo -e "${YELLOW}[DRY-RUN]${RESET} Would execute: $*"; }

# Escape a value for safe use as a sed substitution replacement
sed_escape() { printf '%s' "$1" | sed -e 's/[&/\\]/\\&/g'; }

# -----------------------------------------------------------------------------
# Default values
# -----------------------------------------------------------------------------
PROJECT_DIR="$(pwd)"
DRY_RUN=false
SYNDICATE_PROJECTS_OVERRIDE=""
PROJECT_NAME_OVERRIDE=""
ASSUME_YES=false

# -----------------------------------------------------------------------------
# Help
# -----------------------------------------------------------------------------
usage() {
  grep '^#' "$0" | grep -v '#!/' | sed 's/^# \{0,2\}//' | sed 's/^#//'
  exit 0
}

# -----------------------------------------------------------------------------
# Argument parsing (matching syndicate-init.sh style)
# -----------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)           DRY_RUN=true;                    shift ;;
    --syndicate-projects) SYNDICATE_PROJECTS_OVERRIDE="$2"; shift 2 ;;
    --project)           PROJECT_NAME_OVERRIDE="$2";       shift 2 ;;
    --yes|-y)            ASSUME_YES=true;                  shift ;;
    --help|-h)           usage ;;
    -*) log_error "Unknown option: $1"; exit 1 ;;
    *) PROJECT_DIR="$1"; shift ;;
  esac
done

# Resolve PROJECT_DIR to absolute path
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"

# Derive PROJECT_NAME
if [[ -n "$PROJECT_NAME_OVERRIDE" ]]; then
  PROJECT_NAME="$PROJECT_NAME_OVERRIDE"
else
  PROJECT_NAME="$(basename "$PROJECT_DIR")"
fi

# Resolve central repo path
if [[ -n "$SYNDICATE_PROJECTS_OVERRIDE" ]]; then
  CENTRAL_REPO_ROOT="$SYNDICATE_PROJECTS_OVERRIDE"
else
  CENTRAL_REPO_ROOT="$SYNDICATE_PROJECTS_PATH"
fi

CENTRAL_PROJECT_PATH="$CENTRAL_REPO_ROOT/$PROJECT_NAME"
LOCAL_SYNDICATE_PATH="$PROJECT_DIR/$SYNDICATE_DIR"
CENTRAL_README="$CENTRAL_REPO_ROOT/README.md"

# Hash files for verification
PRE_MIGRATION_HASHES="/tmp/pre-migration-hashes-${PROJECT_NAME}-$$.txt"
POST_MIGRATION_HASHES="/tmp/post-migration-hashes-${PROJECT_NAME}-$$.txt"

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
# Helper: Compute SHA-256 hashes of all files under a directory
# Output: sorted list of "hash  relative_filepath" lines
# -----------------------------------------------------------------------------
compute_hashes() {
  local dir="$1"
  local output_file="$2"

  if [[ "$DRY_RUN" == true ]]; then
    dry_run_echo "find '$dir' -type f -exec sha256sum {} + | sort -k2,2 > '$output_file'"
    if [[ -d "$dir" ]]; then
      (cd "$dir" && find . -type f -exec sha256sum {} + 2>/dev/null | sort -k2,2 > "$output_file") || true
    else
      > "$output_file"
    fi
  else
    (cd "$dir" && find . -type f -exec sha256sum {} + 2>/dev/null | sort -k2,2 > "$output_file")
  fi
}

# -----------------------------------------------------------------------------
# Helper: Compare two hash files
# Returns 0 if identical (excluding identities/ entries which may have been
# removed if the directory was empty), 1 if any mismatch or missing file
# -----------------------------------------------------------------------------
compare_hashes() {
  local pre_file="$1"
  local post_file="$2"
  local temp_pre="/tmp/pre-filtered-$$"
  local temp_post="/tmp/post-filtered-$$"

  # Filter out identities/ entries from pre-file (allowed to disappear if dir was empty)
  grep -v '/identities/' "$pre_file" > "$temp_pre" 2>/dev/null || cp "$pre_file" "$temp_pre"
  # Filter out identities/ entries from post-file (should not exist anyway)
  grep -v '/identities/' "$post_file" > "$temp_post" 2>/dev/null || cp "$post_file" "$temp_post"

  if diff -u "$temp_pre" "$temp_post" >/dev/null 2>&1; then
    rm -f "$temp_pre" "$temp_post"
    return 0
  else
    log_error "Hash mismatch detected! Differences:"
    diff -u "$temp_pre" "$temp_post" >&2 || true
    rm -f "$temp_pre" "$temp_post"
    return 1
  fi
}

# -----------------------------------------------------------------------------
# Helper: Update .gitignore in project repo — REPLACE old colocated block with
# new central-mode block. Must actively REPLACE, not skip if block exists.
# -----------------------------------------------------------------------------
update_gitignore() {
  local gitignore_path="$1"

  local new_block="
# The Shim Syndicate — governance is tracked centrally in the syndicate-projects
# repo and symlinked in as .syndicate. Never commit it into this code repo.
.syndicate
"

  if [[ "$DRY_RUN" == true ]]; then
    dry_run_echo "Update $gitignore_path: replace old Syndicate block with central-mode block"
    return 0
  fi

  if [[ ! -f "$gitignore_path" ]]; then
    echo "$new_block" > "$gitignore_path"
    log_ok "Created .gitignore with central-mode block"
    return 0
  fi

  # Check if old colocated block exists (comment containing "The Shim Syndicate"
  # AND ".syndicate/core/.git")
  if grep -q "The Shim Syndicate" "$gitignore_path" && grep -q '\.syndicate/core/\.git' "$gitignore_path"; then
    # Replace the old block with the new one. The old block is THREE lines:
    #   # The Shim Syndicate — ignore core symlink/subtree re-creation artifacts
    #   .syndicate/core/.git
    #   # Keep the rest of .syndicate tracked (...)
    # An earlier version of this logic only matched the first two lines,
    # leaving the trailing "# Keep the rest..." comment behind as stale,
    # misleading residue underneath the new central-mode block (which says
    # the opposite — full ignore, not "keep tracked"). Caught via an
    # independent hash/content verification pass, not the operative's own
    # self-report. Consume that trailing comment line too if present.
    awk -v new_block="$new_block" '
      BEGIN { in_block = 0; after_marker = 0; replaced = 0 }
      /^# The Shim Syndicate/ { in_block = 1; next }
      in_block && /\.syndicate\/core\/\.git/ { in_block = 0; after_marker = 1; next }
      after_marker && /^# Keep the rest/ { after_marker = 0; if (!replaced) { print new_block; replaced = 1 } next }
      after_marker { after_marker = 0; if (!replaced) { print new_block; replaced = 1 } }
      in_block { next }
      { print }
      END { if (!replaced) print new_block }
    ' "$gitignore_path" > "$gitignore_path.tmp" && mv "$gitignore_path.tmp" "$gitignore_path"
    log_ok "Replaced old colocated .gitignore block with central-mode block"
  else
    # No old block found — append new block (should not happen in normal migration
    # but handle gracefully)
    echo "$new_block" >> "$gitignore_path"
    log_ok "Appended central-mode block to .gitignore (no old block found to replace)"
  fi
}

# -----------------------------------------------------------------------------
# Helper: Register project in central README.md (idempotent)
# -----------------------------------------------------------------------------
register_in_central_readme() {
  local central_readme="$1"
  local project_name="$2"
  local hydration_date="$(date -u +%Y-%m-%d)"

  if [[ "$DRY_RUN" == true ]]; then
    dry_run_echo "Register $project_name in $central_readme Projects table (idempotent)"
    return 0
  fi

  if [[ ! -f "$central_readme" ]]; then
    log_warn "Central README.md not found at $central_readme — skipping registration"
    return 0
  fi

  # Check if already registered (idempotent)
  if grep -q "^| $project_name |" "$central_readme"; then
    log_info "$project_name already registered in $central_readme — skipping"
    return 0
  fi

  # Find the Projects table and insert a new row after the header separator
  # Table format: header line, separator line, then data rows
  local new_row="| $project_name | *(register the code repo manually)* | Migrated $hydration_date |"

  # Use awk to insert after the separator line (|---|---|---|)
  awk -v newrow="$new_row" '
    { print }
    /^\| Project \| Code repo \| Notes \|$/ { getline sep; print sep; print newrow; next }
  ' "$central_readme" > "$central_readme.tmp" && mv "$central_readme.tmp" "$central_readme"

  log_ok "Registered $project_name in $central_readme"
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

log_section "Syndicate Governance Migration v${SCRIPT_VERSION}"

if [[ "$DRY_RUN" == true ]]; then
  log_warn "DRY-RUN MODE — no changes will be made."
fi

# -----------------------------------------------------------------------------
# Pre-flight Checks
# -----------------------------------------------------------------------------
log_section "Pre-flight Checks"

# 1. PROJECT_DIR is a git repository
if ! git -C "$PROJECT_DIR" rev-parse --git-dir >/dev/null 2>&1; then
  log_error "PROJECT_DIR is not a git repository: $PROJECT_DIR"
  exit 1
fi
log_ok "Project is a git repository: $PROJECT_DIR"

# 2. PROJECT_DIR/.syndicate exists and is NOT a symlink
if [[ ! -e "$LOCAL_SYNDICATE_PATH" ]]; then
  log_error ".syndicate does not exist at $LOCAL_SYNDICATE_PATH — nothing to migrate"
  exit 1
fi
if [[ -L "$LOCAL_SYNDICATE_PATH" ]]; then
  log_error ".syndicate is already a symlink at $LOCAL_SYNDICATE_PATH — nothing to migrate"
  exit 1
fi
if [[ ! -d "$LOCAL_SYNDICATE_PATH" ]]; then
  log_error ".syndicate exists but is not a directory: $LOCAL_SYNDICATE_PATH"
  exit 1
fi
log_ok ".syndicate exists as a real directory: $LOCAL_SYNDICATE_PATH"

# 3. Central repo exists and is a git repository
if [[ ! -d "$CENTRAL_REPO_ROOT" ]]; then
  log_error "Central repo path does not exist: $CENTRAL_REPO_ROOT"
  exit 1
fi
if ! git -C "$CENTRAL_REPO_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
  log_error "Central repo path is not a git repository: $CENTRAL_REPO_ROOT"
  exit 1
fi
log_ok "Central repo exists and is a git repository: $CENTRAL_REPO_ROOT"

# 4. Central project directory does not already exist
if [[ -e "$CENTRAL_PROJECT_PATH" ]]; then
  log_error "Central project directory already exists: $CENTRAL_PROJECT_PATH"
  log_error "Refusing to overwrite — this is a one-shot migration tool, not a merge tool."
  exit 1
fi
log_ok "Central project path is available: $CENTRAL_PROJECT_PATH"

# -----------------------------------------------------------------------------
# Summary before execution
# -----------------------------------------------------------------------------
log_section "Migration Plan"
echo -e "  ${BOLD}Project:${RESET}              $PROJECT_NAME"
echo -e "  ${BOLD}Project Path:${RESET}         $PROJECT_DIR"
echo -e "  ${BOLD}Central Repo:${RESET}         $CENTRAL_REPO_ROOT"
echo -e "  ${BOLD}Central Project Path:${RESET}  $CENTRAL_PROJECT_PATH"
echo -e "  ${BOLD}Local .syndicate:${RESET}       $LOCAL_SYNDICATE_PATH"
echo ""

if [[ "$DRY_RUN" == true ]]; then
  log_warn "DRY-RUN MODE — previewing actions only."
else
  if [[ "$ASSUME_YES" == true ]]; then
    log_info "--yes supplied — proceeding without prompting."
  else
    read -r -p "Proceed with migration? (y/N): " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
      log_info "Aborted by user."
      exit 0
    fi
  fi
fi

# =============================================================================
# Step 1: Snapshot SHA-256 hashes of every file in .syndicate/ BEFORE moving
# =============================================================================
log_section "Step 1: Snapshotting Pre-Migration Hashes"

compute_hashes "$LOCAL_SYNDICATE_PATH" "$PRE_MIGRATION_HASHES"
pre_count=$(wc -l < "$PRE_MIGRATION_HASHES" | tr -d ' ')
log_ok "Recorded $pre_count file hashes to $PRE_MIGRATION_HASHES"

if [[ "$DRY_RUN" == false && "$pre_count" -eq 0 ]]; then
  log_warn "No files found in .syndicate/ — migration will move an empty directory"
fi

# =============================================================================
# Step 2: Remove .syndicate from project's git index (keep files on disk)
# =============================================================================
log_section "Step 2: Removing .syndicate from Git Index"

exec_or_dry "git -C '$PROJECT_DIR' rm -r --cached '$SYNDICATE_DIR'"
[[ "$DRY_RUN" == true ]] || log_ok "Removed .syndicate from git index (files remain on disk)"

# =============================================================================
# Step 3: Move .syndicate/ to central location
# =============================================================================
log_section "Step 3: Moving .syndicate/ to Central Location"

exec_or_dry "mv '$LOCAL_SYNDICATE_PATH' '$CENTRAL_PROJECT_PATH'"
[[ "$DRY_RUN" == true ]] || log_ok "Moved .syndicate/ → $CENTRAL_PROJECT_PATH"

# =============================================================================
# Step 4: Remove empty stray identities/ directory if present
# =============================================================================
log_section "Step 4: Cleaning Up Stray identities/ Directory"

IDENTITIES_DIR="$CENTRAL_PROJECT_PATH/identities"
if [[ "$DRY_RUN" == true ]]; then
  dry_run_echo "if [[ -d '$IDENTITIES_DIR' && -z \"\$(ls -A '$IDENTITIES_DIR')\" ]]; then rmdir '$IDENTITIES_DIR'; fi"
else
  if [[ -d "$IDENTITIES_DIR" && -z "$(ls -A "$IDENTITIES_DIR")" ]]; then
    rmdir "$IDENTITIES_DIR"
    log_ok "Removed empty identities/ directory (stale artifact)"
  elif [[ -d "$IDENTITIES_DIR" ]]; then
    log_info "identities/ directory exists and is not empty — leaving intact"
  else
    log_info "No identities/ directory present — nothing to clean"
  fi
fi

# =============================================================================
# Step 5: Re-verify zero data loss with full hash comparison
# =============================================================================
log_section "Step 5: Verifying Zero Data Loss (Hash Comparison)"

compute_hashes "$CENTRAL_PROJECT_PATH" "$POST_MIGRATION_HASHES"
post_count=$(wc -l < "$POST_MIGRATION_HASHES" | tr -d ' ')
log_ok "Recorded $post_count file hashes at new location"

if [[ "$DRY_RUN" == false ]]; then
  if compare_hashes "$PRE_MIGRATION_HASHES" "$POST_MIGRATION_HASHES"; then
    log_ok "Hash comparison PASSED — zero data loss verified"
  else
    log_error "Hash comparison FAILED — migration aborted, data integrity not guaranteed"
    exit 1
  fi
else
  log_info "DRY-RUN: Hash comparison would be performed here"
fi

# =============================================================================
# Step 6: Create symlink
# =============================================================================
log_section "Step 6: Creating .syndicate Symlink"

exec_or_dry "ln -s '$CENTRAL_PROJECT_PATH' '$LOCAL_SYNDICATE_PATH'"
[[ "$DRY_RUN" == true ]] || log_ok "Created symlink: $LOCAL_SYNDICATE_PATH → $CENTRAL_PROJECT_PATH"

# =============================================================================
# Step 7: Update .gitignore (replace old colocated block with central-mode block)
# =============================================================================
log_section "Step 7: Updating .gitignore"

GITIGNORE_PATH="$PROJECT_DIR/.gitignore"
update_gitignore "$GITIGNORE_PATH"

# =============================================================================
# Step 8: Register project in central README.md (idempotent)
# =============================================================================
log_section "Step 8: Registering Project in Central README"

register_in_central_readme "$CENTRAL_README" "$PROJECT_NAME"

# =============================================================================
# Step 9: Commit in central repo (ONLY this project's dir + README.md)
# =============================================================================
log_section "Step 9: Committing Migration in Central Repo"

if [[ "$DRY_RUN" == true ]]; then
  dry_run_echo "git -C '$CENTRAL_REPO_ROOT' add '$PROJECT_NAME/' README.md"
  dry_run_echo "git -C '$CENTRAL_REPO_ROOT' commit -m 'feat(${PROJECT_NAME}): migrate governance to central repo'"
else
  # Check git status first to see what's there
  git -C "$CENTRAL_REPO_ROOT" status --short

  # Add ONLY this project's new directory and README.md
  git -C "$CENTRAL_REPO_ROOT" add "$PROJECT_NAME/" README.md

  # Commit
  if git -C "$CENTRAL_REPO_ROOT" commit -m "feat(${PROJECT_NAME}): migrate governance to central repo" >/dev/null 2>&1; then
    log_ok "Committed migration in central repo: $CENTRAL_REPO_ROOT"
  else
    log_warn "Nothing to commit in central repo (or commit failed) — check manually"
  fi
fi

# =============================================================================
# Step 10: Stage .gitignore change in project repo (do NOT commit)
# =============================================================================
log_section "Step 10: Staging .gitignore in Project Repo"

exec_or_dry "git -C '$PROJECT_DIR' add '.gitignore'"
[[ "$DRY_RUN" == true ]] || log_ok "Staged .gitignore in project repo (commit is operator's decision)"

# =============================================================================
# Done
# =============================================================================
log_section "Migration Complete"

echo ""
echo -e "  ${GREEN}${BOLD}Migration successful!${RESET}"
echo -e "  ${BOLD}Project:${RESET}        $PROJECT_NAME"
echo -e "  ${BOLD}Project repo:${RESET}     $PROJECT_DIR"
echo -e "  ${BOLD}Central governance:${RESET} $CENTRAL_PROJECT_PATH"
echo -e "  ${BOLD}Local .syndicate:${RESET}   symlink → $CENTRAL_PROJECT_PATH"
echo ""
echo -e "  ${BOLD}Next steps:${RESET}"
echo -e "  1. Verify .syndicate is a symlink:  ${CYAN}ls -la $PROJECT_DIR/.syndicate${RESET}"
echo -e "  2. Verify .gitignore has central block:  ${CYAN}cat $PROJECT_DIR/.gitignore${RESET}"
echo -e "  3. Commit .gitignore in project repo:    ${CYAN}git -C $PROJECT_DIR commit -m 'chore: migrate governance to central syndicate-projects'${RESET}"
echo -e "  4. Verify central repo has new commit:   ${CYAN}git -C $CENTRAL_REPO_ROOT log --oneline -1${RESET}"
echo -e "  5. Verify .syndicate no longer tracked in project:  ${CYAN}git -C $PROJECT_DIR ls-files .syndicate/${RESET}"
echo ""

# Cleanup temp hash files
if [[ "$DRY_RUN" == false ]]; then
  rm -f "$PRE_MIGRATION_HASHES" "$POST_MIGRATION_HASHES"
fi