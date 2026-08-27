#!/usr/bin/env bash
# =============================================================================
# launch-operative.sh — Syndicate Operative Launch Wrapper with Resource Governor
# =============================================================================
# USAGE:
#   launch-operative.sh <tier> [--system-prompt <str>] [--append-system-prompt <str>] "<prompt>"
#
# TIERS (Claude — governed):
#   claude-high    → claude-opus-4-7
#   claude-medium  → claude-sonnet-4-6
#   claude-low     → claude-haiku-4-5-20251001
#
# TIERS (Gemini/Pi — ungoverned, pass-through):
#   gemini-high    → gemini-2.5-pro
#   gemini-medium  → gemini-2.5-flash
#   gemini-low     → gemini-2.0-flash-lite
#   pi             → pre-configured via pi.shim.json
#
# GOVERNOR RULES (Claude only):
#   ≥ 75% capacity consumed AND > 60m until reset → HOLD (exit 2)
#   ≥ 90% capacity consumed AND > 20m until reset → HOLD (exit 2)
#   Window resets automatically after 5 hours.
#
# CALIBRATION:
#   On first run, governor initializes with cost_cap_usd = -1 (uncalibrated).
#   Set SYNDICATE_COST_CAP_USD env var or edit ~/.claude/syndicate-governor.json
#   once you observe your 5-hour window ceiling in USD (from --output-format json).
#
# EXIT CODES:
#   0  — success
#   2  — held by governor (capacity threshold active)
#   1  — error
# =============================================================================
set -euo pipefail

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
GOVERNOR_STATE="${SYNDICATE_GOVERNOR_STATE:-$HOME/.claude/syndicate-governor.json}"
WINDOW_MS=18000000        # 5 hours in milliseconds
HOLD_75_CUTOFF_MS=3600000 # 60 minutes
HOLD_90_CUTOFF_MS=1200000 # 20 minutes

RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; RESET='\033[0m'
log_warn()  { echo -e "${YELLOW}[GOVERNOR]${RESET} $*" >&2; }
log_error() { echo -e "${RED}[GOVERNOR]${RESET} $*" >&2; }
log_ok()    { echo -e "${GREEN}[GOVERNOR]${RESET} $*" >&2; }
log_info()  { echo -e "${CYAN}[GOVERNOR]${RESET} $*" >&2; }

# ---------------------------------------------------------------------------
# Tier → model mapping
# ---------------------------------------------------------------------------
tier_to_model() {
  case "$1" in
    claude-high)    echo "claude-opus-4-7" ;;
    claude-medium)  echo "claude-sonnet-4-6" ;;
    claude-low)     echo "claude-haiku-4-5-20251001" ;;
    gemini-high)    echo "gemini-2.5-pro" ;;
    gemini-medium)  echo "gemini-2.5-flash" ;;
    gemini-low)     echo "gemini-2.0-flash-lite" ;;
    pi)                echo "pi" ;;
    # Explicit routing to the top 3 coding-family free models on OpenRouter
    # (selected 2026-08-27 — verified live against openrouter.ai/api/v1/models;
    # re-verify periodically, free-tier slugs churn). Each is the most capable
    # free variant of its family: Nemotron (NVIDIA, 550B MoE, 1M ctx),
    # MiniMax-M3 (1M ctx, agentic-coding flagship), Poolside Laguna-S-2.1
    # (code-specialized lab, 262K ctx — near the ceiling pi's default output
    # reservation allows; families with <~260K context fail with a context-
    # overflow 400 under pi's defaultThinkingLevel).
    pi-nemotron)       echo "pi" ;;
    pi-minimax)        echo "pi" ;;
    pi-poolside)       echo "pi" ;;
    *) log_error "Unknown tier: $1"; exit 1 ;;
  esac
}

# ---------------------------------------------------------------------------
# Governor: initialize state file
# ---------------------------------------------------------------------------
governor_init() {
  if [[ -f "$GOVERNOR_STATE" ]]; then return; fi

  local cap="${SYNDICATE_COST_CAP_USD:--1}"
  python3 - <<EOF
import json, time
state = {
    "window_start_ms": int(time.time() * 1000),
    "window_duration_ms": $WINDOW_MS,
    "cost_accumulated_usd": 0.0,
    "cost_cap_usd": $cap,
    "last_updated": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
}
with open("$GOVERNOR_STATE", "w") as f:
    json.dump(state, f, indent=2)
EOF
  log_warn "Governor initialized at $GOVERNOR_STATE"
  if [[ "$cap" == "-1" ]]; then
    log_warn "cost_cap_usd not set. Set SYNDICATE_COST_CAP_USD or edit the state file to enable gating."
  fi
}

# ---------------------------------------------------------------------------
# Governor: check thresholds — prints STATUS token to stdout, exits 0 always
# ---------------------------------------------------------------------------
governor_check() {
  python3 - <<EOF
import json, sys, time, os

state_file = "$GOVERNOR_STATE"
hold_75_cutoff_ms = $HOLD_75_CUTOFF_MS
hold_90_cutoff_ms = $HOLD_90_CUTOFF_MS

with open(state_file) as f:
    state = json.load(f)

now_ms = int(time.time() * 1000)
window_start = state["window_start_ms"]
window_duration = state["window_duration_ms"]
window_end = window_start + window_duration
time_remaining_ms = max(0, window_end - now_ms)

# Expired window — reset
if now_ms >= window_end:
    state["window_start_ms"] = now_ms
    state["cost_accumulated_usd"] = 0.0
    state["last_updated"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    with open(state_file, "w") as f:
        json.dump(state, f, indent=2)
    print("CLEAR:0.0%:300m_remaining")
    sys.exit(0)

cap = state.get("cost_cap_usd", -1)
if cap <= 0:
    print("UNCALIBRATED")
    sys.exit(0)

accumulated = state["cost_accumulated_usd"]
pct = accumulated / cap
mins_remaining = time_remaining_ms / 60000

label = f"{pct:.1%}:{mins_remaining:.0f}m_remaining"

if pct >= 0.90 and time_remaining_ms > hold_90_cutoff_ms:
    print(f"HOLD_90:{label}")
elif pct >= 0.75 and time_remaining_ms > hold_75_cutoff_ms:
    print(f"HOLD_75:{label}")
else:
    print(f"CLEAR:{label}")
EOF
}

# ---------------------------------------------------------------------------
# Governor: accumulate cost after a successful launch
# ---------------------------------------------------------------------------
governor_update() {
  local cost_usd="$1"
  python3 - <<EOF
import json, time

state_file = "$GOVERNOR_STATE"
with open(state_file) as f:
    state = json.load(f)

state["cost_accumulated_usd"] = round(state["cost_accumulated_usd"] + $cost_usd, 6)
state["last_updated"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())

with open(state_file, "w") as f:
    json.dump(state, f, indent=2)

cap = state.get("cost_cap_usd", -1)
accumulated = state["cost_accumulated_usd"]
if cap > 0:
    pct = accumulated / cap
    print(f"[GOVERNOR] Window: \${accumulated:.4f} / \${cap:.2f} ({pct:.1%} consumed)", flush=True)
else:
    print(f"[GOVERNOR] Window: \${accumulated:.4f} accumulated (uncalibrated)", flush=True)
EOF
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
TIER="${1:-}"
if [[ -z "$TIER" ]]; then
  log_error "Usage: launch-operative.sh <tier> [flags] \"<prompt>\""
  exit 1
fi
shift

MODEL=$(tier_to_model "$TIER")
BACKEND="${TIER%%-*}"  # claude | gemini | pi

# Strip --print if caller passed it (wrapper manages print mode internally)
PASSTHROUGH=()
while [[ $# -gt 0 ]]; do
  [[ "$1" == "--print" ]] && { shift; continue; }
  PASSTHROUGH+=("$1")
  shift
done

# ---------------------------------------------------------------------------
# Governor pre-flight (Claude tiers only)
# ---------------------------------------------------------------------------
if [[ "$BACKEND" == "claude" ]]; then
  governor_init

  STATUS=$(governor_check)
  STATUS_CODE="${STATUS%%:*}"
  STATUS_DETAILS="${STATUS#*:}"

  case "$STATUS_CODE" in
    HOLD_90)
      log_error "CAPACITY HOLD — 90% threshold active (${STATUS_DETAILS})."
      log_error "Operative blocked. Resume in final 20 minutes of the reset window."
      exit 2
      ;;
    HOLD_75)
      log_warn "CAPACITY HOLD — 75% threshold active (${STATUS_DETAILS})."
      log_warn "Operative blocked. Resume in final 60 minutes of the reset window."
      exit 2
      ;;
    UNCALIBRATED)
      log_warn "Governor uncalibrated — proceeding without capacity gating."
      ;;
    CLEAR)
      log_ok "Capacity clear (${STATUS_DETAILS}). Launching ${TIER}."
      ;;
  esac
fi

# ---------------------------------------------------------------------------
# Launch
# ---------------------------------------------------------------------------
TMPFILE=$(mktemp)
trap 'rm -f "$TMPFILE"' EXIT

if [[ "$BACKEND" == "claude" ]]; then
  claude --model "$MODEL" --print --output-format json "${PASSTHROUGH[@]}" > "$TMPFILE"

  # Output plain text result to stdout
  python3 -c "
import json, sys
data = json.load(open('$TMPFILE'))
if data.get('is_error'):
    print(data.get('result', '(no output)'), file=sys.stderr)
    sys.exit(1)
print(data.get('result', ''))
"

  # Accumulate cost
  COST=$(python3 -c "import json; d=json.load(open('$TMPFILE')); print(d.get('total_cost_usd', 0.0))")
  governor_update "$COST" >&2

elif [[ "$BACKEND" == "gemini" ]]; then
  gemini --model "$MODEL" "${PASSTHROUGH[@]}"

elif [[ "$TIER" == "pi" ]]; then
  pi --print "${PASSTHROUGH[@]}"

elif [[ "$TIER" == "pi-nemotron" ]]; then
  pi --provider openrouter --model "nvidia/nemotron-3-ultra-550b-a55b:free" --print "${PASSTHROUGH[@]}"

elif [[ "$TIER" == "pi-minimax" ]]; then
  pi --provider openrouter --model "minimax/minimax-m3:free" --print "${PASSTHROUGH[@]}"

elif [[ "$TIER" == "pi-poolside" ]]; then
  pi --provider openrouter --model "poolside/laguna-s-2.1:free" --print "${PASSTHROUGH[@]}"

else
  log_error "Unrecognized backend: $BACKEND"
  exit 1
fi
