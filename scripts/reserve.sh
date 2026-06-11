#!/usr/bin/env bash
# =============================================================================
# reserve.sh — Syndicate Resource Reservation Registry Tool
# =============================================================================
# Version: 1.0.0
# Repository: jhjessup/the-shim-syndicate
#
# DESCRIPTION:
#   Implements the v3.4.0 "Agent Safety & Concurrency" mechanism (ORACLE §6.3).
#   Agents MUST claim file paths in the reservation registry before mutating
#   them, and MUST NOT modify paths locked by another task. This script is the
#   only sanctioned way to mutate RESERVATIONS.json — manual edits are
#   prohibited.
#
# REGISTRY RESOLUTION (first match wins):
#   1. $SYNDICATE_RESERVATIONS                              (explicit override)
#   2. .syndicate/vault/<branch-sanitized>/RESERVATIONS.json (mission branch)
#   3. .syndicate/vault/RESERVATIONS.json                    (project-level)
#   `claim` creates the registry at location (2) if none exists yet.
#
# USAGE:
#   reserve.sh claim --task <TASK-ID> --agent <handle> --paths <a,b,c> [--pid <pid>]
#   reserve.sh release --task <TASK-ID>
#   reserve.sh status
#   reserve.sh sweep
#
# LOCK SEMANTICS:
#   - Locks are keyed by task_id and carry: agent, paths[], pid, claimed_at,
#     expires_at (claimed_at + 4 hours, UTC ISO-8601).
#   - A lock is STALE if it has expired OR its PID is no longer running
#     (pid 0/null counts as dead). Stale locks never block a claim.
#   - `claim` exits 2 if any requested path is held by a DIFFERENT task whose
#     lock is still valid.
#   - `sweep` removes all stale locks (ORACLE §6.3 RULE_4).
#
# EXIT CODES:
#   0 — success
#   1 — usage / environment error
#   2 — claim refused (path conflict with a valid lock)
# =============================================================================
set -euo pipefail

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
RESET='\033[0m'

LOCK_TTL_SECONDS=$((4 * 3600))   # 4-hour expiry (ORACLE §6.3 RULE_4)

usage() {
  cat <<'EOF'
Usage: reserve.sh <claim|release|status|sweep> [args]

  claim   --task <TASK-ID> --agent <handle> --paths <comma,separated,paths>
          [--pid <pid>]            Claim paths for a task (exit 2 on conflict)
  release --task <TASK-ID>         Release a task's lock (idempotent)
  status                           Pretty-print all locks with validity
  sweep                            Remove expired / dead-PID locks
EOF
}

require_jq() {
  command -v jq >/dev/null 2>&1 || {
    echo -e "${RED}[FAIL]${RESET} reserve.sh requires jq." >&2
    exit 1
  }
}

# ---------------------------------------------------------------------------
# Registry resolution
# ---------------------------------------------------------------------------
branch_vault_registry() {
  local branch sanitized
  # symbolic-ref handles unborn branches (fresh repos); rev-parse is fallback.
  branch="$(git symbolic-ref --short -q HEAD 2>/dev/null \
    || git rev-parse --abbrev-ref HEAD 2>/dev/null \
    || echo "UNKNOWN")"
  sanitized="${branch//\//-}"
  echo ".syndicate/vault/${sanitized}/RESERVATIONS.json"
}

# Prints the registry path to use. If $2 == "create", a missing registry is
# initialized at the branch-vault location (b).
resolve_registry() {
  local mode="${1:-read}"
  local branch_reg project_reg
  branch_reg="$(branch_vault_registry)"
  project_reg=".syndicate/vault/RESERVATIONS.json"

  if [[ -n "${SYNDICATE_RESERVATIONS:-}" ]]; then
    if [[ "$mode" == "create" && ! -f "$SYNDICATE_RESERVATIONS" ]]; then
      init_registry "$SYNDICATE_RESERVATIONS"
    fi
    echo "$SYNDICATE_RESERVATIONS"
    return 0
  fi
  if [[ -f "$branch_reg" ]]; then echo "$branch_reg"; return 0; fi
  if [[ -f "$project_reg" ]]; then echo "$project_reg"; return 0; fi
  if [[ "$mode" == "create" ]]; then
    init_registry "$branch_reg"
    echo "$branch_reg"
    return 0
  fi
  return 1
}

init_registry() {
  local reg="$1" project_name
  project_name="$(basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)")"
  mkdir -p "$(dirname "$reg")"
  jq -n --arg name "$project_name" \
    '{project_name: $name, active_locks: {}}' > "$reg"
  echo -e "${CYAN}[INFO]${RESET} Initialized reservation registry: $reg" >&2
}

# Atomic write: stdin (JSON) -> registry via temp file + mv.
write_registry() {
  local reg="$1" tmp
  tmp="$(mktemp "${reg}.XXXXXX")"
  cat > "$tmp"
  mv "$tmp" "$reg"
}

# ---------------------------------------------------------------------------
# Lock validity (shared by claim, status, sweep)
# ---------------------------------------------------------------------------
iso_to_epoch() { date -u -d "$1" +%s 2>/dev/null || echo 0; }

pid_alive() {
  local pid="$1"
  [[ -n "$pid" && "$pid" != "null" && "$pid" != "0" ]] || return 1
  kill -0 "$pid" 2>/dev/null
}

# Prints VALID | EXPIRED | DEAD-PID for a lock.
lock_state() {
  local expires_at="$1" pid="$2" now
  now="$(date -u +%s)"
  if (( now > $(iso_to_epoch "$expires_at") )); then
    echo "EXPIRED"
  elif ! pid_alive "$pid"; then
    echo "DEAD-PID"
  else
    echo "VALID"
  fi
}

# ---------------------------------------------------------------------------
# Subcommands
# ---------------------------------------------------------------------------
cmd_claim() {
  local task="" agent="" paths_csv="" pid="$PPID"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --task)  task="$2"; shift 2 ;;
      --agent) agent="$2"; shift 2 ;;
      --paths) paths_csv="$2"; shift 2 ;;
      --pid)   pid="$2"; shift 2 ;;
      *) echo -e "${RED}[FAIL]${RESET} Unknown claim option: $1" >&2; usage >&2; exit 1 ;;
    esac
  done
  [[ -n "$task" && -n "$agent" && -n "$paths_csv" ]] || {
    echo -e "${RED}[FAIL]${RESET} claim requires --task, --agent, and --paths." >&2
    exit 1
  }

  local reg
  reg="$(resolve_registry create)"

  local paths_json
  paths_json="$(jq -nc --arg csv "$paths_csv" '$csv | split(",") | map(gsub("^\\s+|\\s+$"; "")) | map(select(length > 0))')"

  # Conflict check: any requested path held by a DIFFERENT task with a VALID lock.
  local conflicts="" lock_task lock_expires lock_pid lock_agent
  while IFS=$'\t' read -r lock_task lock_expires lock_pid lock_agent; do
    [[ -n "$lock_task" && "$lock_task" != "$task" ]] || continue
    [[ "$(lock_state "$lock_expires" "$lock_pid")" == "VALID" ]] || continue
    local overlap
    overlap="$(jq -r --argjson req "$paths_json" --arg t "$lock_task" \
      '.active_locks[$t].paths as $held | $req | map(select(. as $p | $held | index($p))) | join(", ")' "$reg")"
    if [[ -n "$overlap" ]]; then
      conflicts+="  - ${overlap} (locked by task ${lock_task}, agent ${lock_agent})"$'\n'
    fi
  done < <(jq -r '.active_locks | to_entries[] | [.key, .value.expires_at, (.value.pid|tostring), .value.agent] | @tsv' "$reg")

  if [[ -n "$conflicts" ]]; then
    echo -e "${RED}${BOLD}[REFUSED]${RESET} Path conflict — the following paths are locked by another valid task:" >&2
    printf '%s' "$conflicts" >&2
    echo -e "  Run ${CYAN}reserve.sh status${RESET} to inspect, or wait for release/expiry." >&2
    exit 2
  fi

  local claimed_at expires_at
  claimed_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  expires_at="$(date -u -d "@$(( $(date -u +%s) + LOCK_TTL_SECONDS ))" +%Y-%m-%dT%H:%M:%SZ)"

  jq --arg task "$task" --arg agent "$agent" --argjson paths "$paths_json" \
     --argjson pid "$pid" --arg claimed "$claimed_at" --arg expires "$expires_at" \
     '.active_locks[$task] = {task_id: $task, agent: $agent, paths: $paths, pid: $pid, claimed_at: $claimed, expires_at: $expires}' \
     "$reg" | write_registry "$reg"

  echo -e "${GREEN}[CLAIMED]${RESET} $task by $agent (pid $pid) — expires $expires_at"
  echo -e "  Registry: $reg"
  jq -r --arg t "$task" '.active_locks[$t].paths[] | "  - \(.)"' "$reg"
}

cmd_release() {
  local task=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --task) task="$2"; shift 2 ;;
      *) echo -e "${RED}[FAIL]${RESET} Unknown release option: $1" >&2; usage >&2; exit 1 ;;
    esac
  done
  [[ -n "$task" ]] || { echo -e "${RED}[FAIL]${RESET} release requires --task." >&2; exit 1; }

  local reg
  if ! reg="$(resolve_registry)"; then
    echo -e "${YELLOW}[NOTE]${RESET} No reservation registry found — nothing to release."
    exit 0
  fi

  if jq -e --arg t "$task" '.active_locks | has($t)' "$reg" >/dev/null; then
    jq --arg t "$task" 'del(.active_locks[$t])' "$reg" | write_registry "$reg"
    echo -e "${GREEN}[RELEASED]${RESET} $task — lock removed from $reg"
  else
    echo -e "${YELLOW}[NOTE]${RESET} No lock held by task $task — nothing to release (idempotent)."
  fi
}

cmd_status() {
  local reg
  if ! reg="$(resolve_registry)"; then
    echo -e "${YELLOW}[NOTE]${RESET} No reservation registry found."
    exit 0
  fi
  echo -e "${CYAN}${BOLD}[RESERVATIONS]${RESET} $reg"
  local count
  count="$(jq -r '.active_locks | length' "$reg")"
  if [[ "$count" == "0" ]]; then
    echo "  (no active locks)"
    return 0
  fi
  local task expires pid agent claimed state color
  while IFS=$'\t' read -r task agent pid claimed expires; do
    state="$(lock_state "$expires" "$pid")"
    case "$state" in
      VALID)    color="$GREEN" ;;
      EXPIRED)  color="$YELLOW" ;;
      DEAD-PID) color="$RED" ;;
    esac
    echo -e "  ${color}[$state]${RESET} $task — agent: $agent, pid: $pid"
    echo "          claimed: $claimed  expires: $expires"
    jq -r --arg t "$task" '.active_locks[$t].paths[] | "          path: \(.)"' "$reg"
  done < <(jq -r '.active_locks | to_entries[] | [.key, .value.agent, (.value.pid|tostring), .value.claimed_at, .value.expires_at] | @tsv' "$reg")
}

cmd_sweep() {
  local reg
  if ! reg="$(resolve_registry)"; then
    echo -e "${YELLOW}[NOTE]${RESET} No reservation registry found — nothing to sweep."
    exit 0
  fi
  local removed=0 task expires pid state
  while IFS=$'\t' read -r task expires pid; do
    state="$(lock_state "$expires" "$pid")"
    if [[ "$state" != "VALID" ]]; then
      jq --arg t "$task" 'del(.active_locks[$t])' "$reg" | write_registry "$reg"
      echo -e "${YELLOW}[SWEPT]${RESET} $task — removed ($state)"
      removed=$((removed + 1))
    fi
  done < <(jq -r '.active_locks | to_entries[] | [.key, .value.expires_at, (.value.pid|tostring)] | @tsv' "$reg")
  if (( removed == 0 )); then
    echo -e "${GREEN}[CLEAN]${RESET} No stale locks in $reg"
  else
    echo -e "${GREEN}[DONE]${RESET} Removed $removed stale lock(s) from $reg"
  fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
require_jq
SUBCOMMAND="${1:-}"
[[ -n "$SUBCOMMAND" ]] || { usage >&2; exit 1; }
shift

case "$SUBCOMMAND" in
  claim)   cmd_claim "$@" ;;
  release) cmd_release "$@" ;;
  status)  cmd_status "$@" ;;
  sweep)   cmd_sweep "$@" ;;
  -h|--help|help) usage ;;
  *) echo -e "${RED}[FAIL]${RESET} Unknown subcommand: $SUBCOMMAND" >&2; usage >&2; exit 1 ;;
esac
