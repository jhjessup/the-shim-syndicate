#!/usr/bin/env bash
# =============================================================================
# audit-trace.sh — Evidence-Bound Syndicate-Audit-Trace Generator/Verifier
# =============================================================================
# Version: 1.0.0
# Repository: jhjessup/the-shim-syndicate
#
# RATIONALE (evidence binding):
#   The legacy Syndicate-Audit-Trace trailer is self-attested — any agent can
#   mint one without a Gavel audit ever happening. This tool closes that gap
#   by binding the trailer to a written audit record: `generate` appends an
#   audit entry to AUDIT_LOG.md, hashes that entry (sha256, first 12 hex
#   chars), records the hash in the log as `AUDIT_TRACE_HASH: <hash>`, and
#   emits a trailer carrying the same hash. The commit-msg hook can then
#   verify the trailer's hash against the log — a forged trailer has no
#   matching AUDIT_TRACE_HASH entry and is rejected.
#
# TRAILER FORMATS:
#   Legacy (2-field, still accepted by hooks during the transition):
#     Syndicate-Audit-Trace: @gavel <STATUS> — <ISO-8601>
#   Evidence-bound (3-field, the verifiable form — produced by this tool):
#     Syndicate-Audit-Trace: @gavel <STATUS> — <ISO-8601> — <12-hex-hash>
#
# USAGE:
#   audit-trace.sh generate --status <PASS|"CONDITIONAL PASS"> \
#                           --log <path/to/AUDIT_LOG.md> [--scope "<text>"]
#       Appends the audit entry + AUDIT_TRACE_HASH to the log and prints the
#       evidence-bound trailer line to stdout.
#
#   audit-trace.sh verify --hash <12hex> --log <path>
#   audit-trace.sh verify --trailer "<full trailer line>" --log <path>
#       Exits 0 ([PASS]) if AUDIT_TRACE_HASH: <hash> exists in the log,
#       1 ([FAIL]) otherwise.
#
# DEPENDENCIES: bash, coreutils (sha256sum, date).
# =============================================================================
set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
CYAN='\033[0;36m'
RESET='\033[0m'

usage() {
  cat <<'EOF'
Usage: audit-trace.sh <generate|verify> [args]

  generate --status <PASS|"CONDITIONAL PASS"> --log <AUDIT_LOG.md> [--scope "<text>"]
  verify   (--hash <12hex> | --trailer "<trailer line>") --log <AUDIT_LOG.md>
EOF
}

cmd_generate() {
  local status="" log="" scope=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --status) status="$2"; shift 2 ;;
      --log)    log="$2"; shift 2 ;;
      --scope)  scope="$2"; shift 2 ;;
      *) echo -e "${RED}[FAIL]${RESET} Unknown generate option: $1" >&2; usage >&2; exit 1 ;;
    esac
  done
  [[ -n "$status" && -n "$log" ]] || {
    echo -e "${RED}[FAIL]${RESET} generate requires --status and --log." >&2; exit 1
  }
  case "$status" in
    PASS|"CONDITIONAL PASS") ;;
    *) echo -e "${RED}[FAIL]${RESET} --status must be PASS or \"CONDITIONAL PASS\" (a FAIL trace is never a valid commit state)." >&2; exit 1 ;;
  esac
  [[ -f "$log" ]] || {
    echo -e "${RED}[FAIL]${RESET} Audit log not found: $log" >&2; exit 1
  }

  local ts entry hash
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  entry="[${ts}] [GAVEL] AUDIT TRACE ISSUED — ${scope:-unscoped}
STATUS: ${status}"
  hash="$(printf '%s' "$entry" | sha256sum | cut -c1-12)"

  {
    echo ""
    printf '%s\n' "$entry"
    echo "AUDIT_TRACE_HASH: ${hash}"
  } >> "$log"

  echo -e "${CYAN}[GAVEL]${RESET} Audit entry appended to ${log} (hash ${hash})." >&2
  echo "Syndicate-Audit-Trace: @gavel ${status} — ${ts} — ${hash}"
}

cmd_verify() {
  local hash="" trailer="" log=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --hash)    hash="$2"; shift 2 ;;
      --trailer) trailer="$2"; shift 2 ;;
      --log)     log="$2"; shift 2 ;;
      *) echo -e "${RED}[FAIL]${RESET} Unknown verify option: $1" >&2; usage >&2; exit 1 ;;
    esac
  done
  [[ -n "$log" ]] || { echo -e "${RED}[FAIL]${RESET} verify requires --log." >&2; exit 1; }

  if [[ -z "$hash" && -n "$trailer" ]]; then
    hash="$(printf '%s' "$trailer" | grep -oE '[0-9a-f]{12}[[:space:]]*$' | tr -d '[:space:]' || true)"
    [[ -n "$hash" ]] || {
      echo -e "${RED}[FAIL]${RESET} No 12-hex audit hash found in trailer: $trailer" >&2; exit 1
    }
  fi
  [[ "$hash" =~ ^[0-9a-f]{12}$ ]] || {
    echo -e "${RED}[FAIL]${RESET} --hash must be exactly 12 lowercase hex characters." >&2; exit 1
  }
  [[ -f "$log" ]] || {
    echo -e "${RED}[FAIL]${RESET} Audit log not found: $log" >&2; exit 1
  }

  if grep -qE "^AUDIT_TRACE_HASH:[[:space:]]*${hash}[[:space:]]*$" "$log"; then
    echo -e "${GREEN}[PASS]${RESET} Hash ${hash} is evidence-bound: matching AUDIT_TRACE_HASH entry found in ${log}."
    exit 0
  else
    echo -e "${RED}[FAIL]${RESET} Hash ${hash} has NO matching AUDIT_TRACE_HASH entry in ${log} — trailer is not evidence-bound."
    exit 1
  fi
}

SUBCOMMAND="${1:-}"
[[ -n "$SUBCOMMAND" ]] || { usage >&2; exit 1; }
shift

case "$SUBCOMMAND" in
  generate) cmd_generate "$@" ;;
  verify)   cmd_verify "$@" ;;
  -h|--help|help) usage ;;
  *) echo -e "${RED}[FAIL]${RESET} Unknown subcommand: $SUBCOMMAND" >&2; usage >&2; exit 1 ;;
esac
