#!/usr/bin/env bash
# =============================================================================
# syndicate-session.sh — The Shim Syndicate tmux Session Manager
# =============================================================================
# Version: 2.1.0
# Repository: jhjessup/the-shim-syndicate
#
# DESCRIPTION:
#   Creates the Syndicate tmux window layout in a headless / remote terminal
#   environment. On start or attach it loads .env, detects the current Git
#   branch (mission/ branches resolve the branch-specific ORACLE.md and
#   project-map.json), exports SYNDICATE_* variables into the tmux session,
#   and pre-types each agent's launch command into its window for operator
#   confirmation. It does NOT auto-start agents: the lead window receives a
#   full working claude command; the ledger and gavel windows receive clearly
#   labeled TEMPLATE stubs (correct CLI flags vary) carrying the real identity
#   and context file paths. The operator reviews each line and presses Enter.
#
# USAGE:
#   bash syndicate-session.sh [COMMAND] [OPTIONS]
#
# COMMANDS:
#   start     Create a new Syndicate tmux session (fails if one exists)
#   attach    Attach to the session, creating it first if absent (default)
#   reload    Hot-reload mission context for the current branch (no session restart)
#   status    Print session state, current branch, and loaded context paths
#   kill      Terminate the active Syndicate session
#
# OPTIONS:
#   --session <name>   tmux session name           (default: syndicate)
#   --project <path>   Project root directory       (default: cwd)
#   --env <file>       Path to .env file            (default: <project>/.env)
#   --dry-run          Preview actions without executing
#   --help             Show this help message
#
# ENVIRONMENT VARIABLES (pulled from shell or .env — never hardcoded):
#   ANTHROPIC_API_KEY        Required for The Lead (Claude)
#   GOOGLE_API_KEY           Required for The Ledger (Gemini)
#   OPENCODE_MODEL           Override default model for The Gavel
#   SYNDICATE_SESSION_NAME   Override default tmux session name
#   SYNDICATE_CORE_PATH      Override path to the Syndicate Core repo
#
# TMUX WINDOW LAYOUT:
#   Window 0 — mission   (branch status, mission context summary)
#   Window 1 — lead      (claude CLI — Principal Architect)
#   Window 2 — ledger    (gemini CLI — Context Librarian)
#   Window 3 — gavel     (opencode/ollama CLI — Audit Authority)
#
# =============================================================================
set -euo pipefail

# -----------------------------------------------------------------------------
# Constants
# -----------------------------------------------------------------------------
SCRIPT_VERSION="2.1.0"
SYNDICATE_DIR=".syndicate"

RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

log_info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
log_ok()      { echo -e "${GREEN}[OK]${RESET}    $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
log_error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; }
log_section() { echo -e "\n${BOLD}── $* ──${RESET}"; }
dry_run_echo(){ echo -e "${YELLOW}[DRY-RUN]${RESET} Would execute: $*"; }

# -----------------------------------------------------------------------------
# Defaults
# -----------------------------------------------------------------------------
COMMAND="attach"
SESSION_NAME="${SYNDICATE_SESSION_NAME:-syndicate}"
PROJECT_DIR="$(pwd)"
ENV_FILE=""
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
    start|attach|reload|status|kill)
      COMMAND="$1"; shift ;;
    --session)   SESSION_NAME="$2"; shift 2 ;;
    --project)   PROJECT_DIR="$2";  shift 2 ;;
    --env)       ENV_FILE="$2";     shift 2 ;;
    --dry-run)   DRY_RUN=true;      shift   ;;
    --help|-h)   usage ;;
    *) log_error "Unknown option: $1"; exit 1 ;;
  esac
done

# Default env file if not specified
if [[ -z "$ENV_FILE" ]]; then
  ENV_FILE="$PROJECT_DIR/.env"
fi

STUB_DIR="$PROJECT_DIR/$SYNDICATE_DIR"

# -----------------------------------------------------------------------------
# Helper: execute or dry-run
# -----------------------------------------------------------------------------
exec_or_dry() {
  if [[ "$DRY_RUN" == true ]]; then
    dry_run_echo "$*"
  else
    eval "$*"
  fi
}

# -----------------------------------------------------------------------------
# Step 1: Load API keys from .env (non-destructive — only sets if not already set)
# -----------------------------------------------------------------------------
load_env() {
  if [[ -f "$ENV_FILE" ]]; then
    log_info "Loading environment from $ENV_FILE"
    # Source only KEY=value lines; skip comments and blank lines
    set -o allexport
    # shellcheck source=/dev/null
    source <(grep -E '^[A-Z_]+=.+' "$ENV_FILE" | grep -v '^#')
    set +o allexport
    log_ok ".env loaded."
  else
    log_warn ".env not found at $ENV_FILE — relying on shell environment."
  fi

  # Validate required keys
  local missing=()
  [[ -z "${ANTHROPIC_API_KEY:-}" ]] && missing+=("ANTHROPIC_API_KEY")
  [[ -z "${GOOGLE_API_KEY:-}" ]]    && missing+=("GOOGLE_API_KEY")

  if [[ ${#missing[@]} -gt 0 ]]; then
    log_warn "Missing API keys (some agents will be unavailable): ${missing[*]}"
    log_warn "Set them in $ENV_FILE or export from your shell before launching."
  fi
}

# -----------------------------------------------------------------------------
# Step 2: Detect Git branch and resolve mission context
# -----------------------------------------------------------------------------
detect_mission_context() {
  if ! git -C "$PROJECT_DIR" rev-parse --git-dir &>/dev/null; then
    log_error "$PROJECT_DIR is not a git repository."
    exit 1
  fi

  CURRENT_BRANCH="$(git -C "$PROJECT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "DETACHED")"
  IS_MISSION=false
  MISSION_NAME=""
  MISSION_VAULT=""
  MISSION_ORACLE=""
  MISSION_MAP=""

  if [[ "$CURRENT_BRANCH" == mission/* ]]; then
    IS_MISSION=true
    # Sanitize branch name for filesystem use: replace / with -
    MISSION_NAME="${CURRENT_BRANCH#mission/}"
    MISSION_VAULT="$STUB_DIR/vault/${CURRENT_BRANCH//\//-}"
    MISSION_ORACLE="$MISSION_VAULT/ORACLE.md"
    MISSION_MAP="$MISSION_VAULT/project-map.json"

    log_ok "Mission branch detected: ${BOLD}$CURRENT_BRANCH${RESET}"
    log_info "Mission vault: $MISSION_VAULT"

    # Warn if vault hasn't been initialized (run syndicate-init.sh --mission first)
    if [[ ! -d "$MISSION_VAULT" ]]; then
      log_warn "Mission vault not found at $MISSION_VAULT."
      log_warn "Run: bash syndicate-init.sh --mission to initialize this mission."
    fi
  else
    log_info "Branch: ${BOLD}$CURRENT_BRANCH${RESET} (not a mission branch — standard context loaded)"
    MISSION_ORACLE="$STUB_DIR/ORACLE.md"
    MISSION_MAP="$STUB_DIR/project-map.json"
  fi
}

# -----------------------------------------------------------------------------
# Step 3: Resolve identity paths and compose per-agent launch commands
#
# Sets GLOBALS consumed by create_session():
#   lead_identity / ledger_identity / gavel_identity — resolved identity paths
#   LEAD_CMD   — full working claude command (flags per README.md
#                "Starting The Lead": --system-prompt + --append-system-prompt)
#   LEDGER_CMD — TEMPLATE stub: correct gemini CLI flags are uncertain, so the
#                window receives the real file paths for the operator to adapt
#   GAVEL_CMD  — TEMPLATE stub (opencode) or plain ollama run + paste hint
# -----------------------------------------------------------------------------
build_agent_commands() {
  if [[ -f "$MISSION_ORACLE" ]]; then
    log_ok "ORACLE.md context: $MISSION_ORACLE"
  else
    log_warn "ORACLE.md not found at $MISSION_ORACLE — agents will start without project context."
  fi

  if [[ -f "$MISSION_MAP" ]]; then
    log_ok "project-map.json context: $MISSION_MAP"
  else
    log_warn "project-map.json not found at $MISSION_MAP"
  fi

  # Identity file paths (prefer mission vault override, fall back to core).
  # Deliberately NOT local — create_session() reads these globals.
  local core_path="${SYNDICATE_CORE_PATH:-$STUB_DIR/core}"

  lead_identity="$core_path/identities/THE_LEAD.md"
  ledger_identity="$core_path/identities/THE_LEDGER.md"
  gavel_identity="$core_path/identities/THE_GAVEL.md"

  # Check for mission-local identity overrides in vault
  [[ -f "$MISSION_VAULT/THE_LEAD.md"   ]] && lead_identity="$MISSION_VAULT/THE_LEAD.md"
  [[ -f "$MISSION_VAULT/THE_LEDGER.md" ]] && ledger_identity="$MISSION_VAULT/THE_LEDGER.md"
  [[ -f "$MISSION_VAULT/THE_GAVEL.md"  ]] && gavel_identity="$MISSION_VAULT/THE_GAVEL.md"

  # --- The Lead: claude CLI (documented flags — see README.md "Starting The Lead") ---
  LEAD_CMD="claude --system-prompt \"\$(cat '${lead_identity}')\""
  if [[ -f "$MISSION_ORACLE" ]]; then
    LEAD_CMD+=" --append-system-prompt \"\$(cat '${MISSION_ORACLE}')\""
  fi

  # --- The Ledger: gemini CLI — flags vary by CLI version; provide a stub + real paths ---
  LEDGER_CMD="gemini  # TEMPLATE — adapt flags. identity: ${ledger_identity} | context: ${MISSION_ORACLE} ${MISSION_MAP}"

  # --- The Gavel: opencode or ollama ---
  local gavel_model="${OPENCODE_MODEL:-qwen2.5-coder:32b}"
  if command -v opencode &>/dev/null; then
    GAVEL_CMD="opencode --model '${gavel_model}'  # TEMPLATE — adapt flags. identity: ${gavel_identity} | context: ${MISSION_ORACLE}"
  else
    GAVEL_CMD="ollama run '${gavel_model}'  # then paste identity as system prompt: ${gavel_identity}"
    log_warn "opencode not found — The Gavel will use ollama run."
    log_warn "Manually paste $gavel_identity contents as system prompt."
  fi
}

# -----------------------------------------------------------------------------
# Step 4: Print status banner for the mission window (window 0)
# -----------------------------------------------------------------------------
mission_banner() {
  local banner
  banner="$(cat <<BANNER
╔══════════════════════════════════════════════════════════════════╗
║           THE SHIM SYNDICATE — SESSION CONTROL v${SCRIPT_VERSION}           ║
╠══════════════════════════════════════════════════════════════════╣
║  Branch  : ${CURRENT_BRANCH}
║  Mission : $([ "$IS_MISSION" == true ] && echo "$MISSION_NAME" || echo "— (not a mission branch)")
║  Oracle  : ${MISSION_ORACLE}
║  Map     : ${MISSION_MAP}
║  Vault   : ${MISSION_VAULT:-N/A}
╠══════════════════════════════════════════════════════════════════╣
║  Windows: [0] mission  [1] lead  [2] ledger  [3] gavel          ║
║  Switch : Ctrl-b + <window number>                               ║
╚══════════════════════════════════════════════════════════════════╝

  [1] lead   → claude  (Principal Architect)
  [2] ledger → gemini  (Context Librarian — 1M token context)
  [3] gavel  → local   (Audit Authority — pre-commit enforcement)

Branch Integrity Rules:
  • Commits to 'main' are BLOCKED — use mission/ branches
  • Every commit requires a Syndicate-Audit-Trace trailer
  • The Gavel pre-commit hook is active for this vault

BANNER
)"
  echo "$banner"
}

# -----------------------------------------------------------------------------
# Core: Create tmux session
# -----------------------------------------------------------------------------
create_session() {
  log_section "Creating Syndicate tmux Session: $SESSION_NAME"

  if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
    if [[ "$COMMAND" == "start" ]]; then
      log_error "Session '$SESSION_NAME' already exists. Use 'attach' or 'kill' first."
      exit 1
    fi
    log_info "Session exists — attaching."
    tmux attach-session -t "$SESSION_NAME"
    return
  fi

  if [[ "$DRY_RUN" == true ]]; then
    dry_run_echo "tmux new-session -d -s '$SESSION_NAME' -n mission"
    dry_run_echo "tmux new-window -t '$SESSION_NAME' -n lead"
    dry_run_echo "tmux new-window -t '$SESSION_NAME' -n ledger"
    dry_run_echo "tmux new-window -t '$SESSION_NAME' -n gavel"
    dry_run_echo "tmux send-keys (no Enter) lead   → $LEAD_CMD"
    dry_run_echo "tmux send-keys (no Enter) ledger → $LEDGER_CMD"
    dry_run_echo "tmux send-keys (no Enter) gavel  → $GAVEL_CMD"
    dry_run_echo "tmux attach-session -t '$SESSION_NAME'"
    return
  fi

  # Window 0 — mission control (status display)
  tmux new-session -d -s "$SESSION_NAME" -n "mission" -x 220 -y 50

  # Set environment in session scope (all windows inherit these)
  tmux set-environment -t "$SESSION_NAME" ANTHROPIC_API_KEY "${ANTHROPIC_API_KEY:-}"
  tmux set-environment -t "$SESSION_NAME" GOOGLE_API_KEY    "${GOOGLE_API_KEY:-}"
  tmux set-environment -t "$SESSION_NAME" SYNDICATE_BRANCH  "$CURRENT_BRANCH"
  tmux set-environment -t "$SESSION_NAME" SYNDICATE_ORACLE  "$MISSION_ORACLE"
  tmux set-environment -t "$SESSION_NAME" SYNDICATE_MAP     "$MISSION_MAP"
  [[ -n "$MISSION_VAULT" ]] && \
    tmux set-environment -t "$SESSION_NAME" SYNDICATE_VAULT "$MISSION_VAULT"

  # Print banner in mission window
  tmux send-keys -t "$SESSION_NAME:mission" \
    "cd '$PROJECT_DIR' && clear && cat <<'__BANNER__'
$(mission_banner)
__BANNER__
" Enter

  # Each agent window gets its context echoed (executed), then its launch
  # command PRE-TYPED via send-keys WITHOUT the Enter terminator. This is a
  # deliberate design choice: agents are never auto-started. The operator
  # reviews the typed command — adapting the ledger/gavel TEMPLATE stubs to
  # the locally installed CLI flags — and presses Enter to launch.

  # Window 1 — lead
  tmux new-window -t "$SESSION_NAME" -n "lead"
  tmux send-keys -t "$SESSION_NAME:lead" \
    "cd '$PROJECT_DIR' && echo '[@lead] Loading context...' && echo 'Identity: $lead_identity' && echo 'Oracle  : $MISSION_ORACLE'" Enter
  tmux send-keys -t "$SESSION_NAME:lead" -l "$LEAD_CMD"

  # Window 2 — ledger
  tmux new-window -t "$SESSION_NAME" -n "ledger"
  tmux send-keys -t "$SESSION_NAME:ledger" \
    "cd '$PROJECT_DIR' && echo '[@ledger] Loading context...' && echo 'Identity: $ledger_identity' && echo 'Oracle  : $MISSION_ORACLE' && echo 'Map     : $MISSION_MAP'" Enter
  tmux send-keys -t "$SESSION_NAME:ledger" -l "$LEDGER_CMD"

  # Window 3 — gavel
  tmux new-window -t "$SESSION_NAME" -n "gavel"
  tmux send-keys -t "$SESSION_NAME:gavel" \
    "cd '$PROJECT_DIR' && echo '[@gavel] Audit authority ready.' && echo 'Identity: $gavel_identity' && echo 'Oracle  : $MISSION_ORACLE' && echo '' && echo 'Pre-commit hook: $STUB_DIR/hooks/pre-commit'" Enter
  tmux send-keys -t "$SESSION_NAME:gavel" -l "$GAVEL_CMD"

  # Focus mission window on attach
  tmux select-window -t "$SESSION_NAME:mission"

  log_ok "Session '$SESSION_NAME' created with 4 windows."
  tmux attach-session -t "$SESSION_NAME"
}

# -----------------------------------------------------------------------------
# Core: Reload mission context without destroying the session
# -----------------------------------------------------------------------------
reload_context() {
  log_section "Reloading Mission Context — Branch: $CURRENT_BRANCH"

  if ! tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
    log_error "No active session named '$SESSION_NAME'. Run 'attach' first."
    exit 1
  fi

  exec_or_dry "tmux set-environment -t '$SESSION_NAME' SYNDICATE_BRANCH  '$CURRENT_BRANCH'"
  exec_or_dry "tmux set-environment -t '$SESSION_NAME' SYNDICATE_ORACLE  '$MISSION_ORACLE'"
  exec_or_dry "tmux set-environment -t '$SESSION_NAME' SYNDICATE_MAP     '$MISSION_MAP'"
  [[ -n "$MISSION_VAULT" ]] && \
    exec_or_dry "tmux set-environment -t '$SESSION_NAME' SYNDICATE_VAULT '$MISSION_VAULT'"

  # Notify all windows of context reload
  for win in lead ledger gavel; do
    if tmux list-windows -t "$SESSION_NAME" -F '#{window_name}' | grep -q "^${win}$"; then
      exec_or_dry "tmux send-keys -t '$SESSION_NAME:$win' '' ''"
      exec_or_dry "tmux display-message -t '$SESSION_NAME:$win' '[Syndicate] Context reloaded: $CURRENT_BRANCH'"
    fi
  done

  log_ok "Context reloaded. New Oracle: $MISSION_ORACLE"
  log_ok "New Map: $MISSION_MAP"
}

# -----------------------------------------------------------------------------
# Core: Print status
# -----------------------------------------------------------------------------
print_status() {
  echo ""
  echo -e "${BOLD}Syndicate Session Status${RESET}"
  echo "  Session name : $SESSION_NAME"
  echo "  tmux alive   : $(tmux has-session -t "$SESSION_NAME" 2>/dev/null && echo YES || echo NO)"
  echo "  Branch       : $CURRENT_BRANCH"
  echo "  Is mission   : $IS_MISSION"
  echo "  Mission name : ${MISSION_NAME:-—}"
  echo "  Vault        : ${MISSION_VAULT:-—}"
  echo "  Oracle       : $MISSION_ORACLE $([ -f "$MISSION_ORACLE" ] && echo "(exists)" || echo "(MISSING)")"
  echo "  Map          : $MISSION_MAP $([ -f "$MISSION_MAP" ] && echo "(exists)" || echo "(MISSING)")"
  echo "  ANTHROPIC_KEY: $([ -n "${ANTHROPIC_API_KEY:-}" ] && echo "set" || echo "MISSING")"
  echo "  GOOGLE_KEY   : $([ -n "${GOOGLE_API_KEY:-}" ] && echo "set" || echo "MISSING")"
  echo ""

  if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
    echo -e "${BOLD}Windows:${RESET}"
    tmux list-windows -t "$SESSION_NAME" -F "  [#{window_index}] #{window_name}  (#{window_active_clients} clients)"
  fi
  echo ""
}

# -----------------------------------------------------------------------------
# Core: Kill session
# -----------------------------------------------------------------------------
kill_session() {
  if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
    exec_or_dry "tmux kill-session -t '$SESSION_NAME'"
    log_ok "Session '$SESSION_NAME' terminated."
  else
    log_warn "No session named '$SESSION_NAME' found."
  fi
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
log_section "Syndicate Session Manager v${SCRIPT_VERSION}"

load_env
detect_mission_context
build_agent_commands

case "$COMMAND" in
  start)   create_session ;;
  attach)  create_session ;;
  reload)  reload_context ;;
  status)  print_status ;;
  kill)    kill_session ;;
  *)
    log_error "Unknown command: $COMMAND"
    usage
    ;;
esac
