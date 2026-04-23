#!/usr/bin/env python3
"""
Thin shim — delegates to the governor state file used by launch-operative.sh.
Kept for backwards compatibility with any scripts that call it directly.

Usage: python3 update_usage.py <cost_usd>
       python3 update_usage.py --status
"""
import json
import sys
import os
import time

STATE_FILE = os.environ.get(
    "SYNDICATE_GOVERNOR_STATE",
    os.path.expanduser("~/.claude/syndicate-governor.json")
)

WINDOW_MS = 18_000_000  # 5 hours


def load_state():
    if not os.path.exists(STATE_FILE):
        print(f"[GOVERNOR] State file not found: {STATE_FILE}", file=sys.stderr)
        print("[GOVERNOR] Run launch-operative.sh once to initialize.", file=sys.stderr)
        sys.exit(1)
    with open(STATE_FILE) as f:
        return json.load(f)


def save_state(state):
    state["last_updated"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    with open(STATE_FILE, "w") as f:
        json.dump(state, f, indent=2)


def maybe_reset(state):
    now_ms = int(time.time() * 1000)
    window_end = state["window_start_ms"] + state.get("window_duration_ms", WINDOW_MS)
    if now_ms >= window_end:
        state["window_start_ms"] = now_ms
        state["cost_accumulated_usd"] = 0.0
        print("[GOVERNOR] Window reset.", file=sys.stderr)
    return state


def update_cost(cost_usd: float):
    state = load_state()
    state = maybe_reset(state)
    state["cost_accumulated_usd"] = round(state["cost_accumulated_usd"] + cost_usd, 6)
    save_state(state)

    cap = state.get("cost_cap_usd", -1)
    accumulated = state["cost_accumulated_usd"]
    if cap > 0:
        pct = accumulated / cap
        print(f"[GOVERNOR] Window: ${accumulated:.4f} / ${cap:.2f} ({pct:.1%} consumed)")
    else:
        print(f"[GOVERNOR] Window: ${accumulated:.4f} accumulated (uncalibrated)")


def print_status():
    state = load_state()
    state = maybe_reset(state)

    now_ms = int(time.time() * 1000)
    window_end = state["window_start_ms"] + state.get("window_duration_ms", WINDOW_MS)
    mins_remaining = max(0, (window_end - now_ms) / 60_000)

    cap = state.get("cost_cap_usd", -1)
    accumulated = state["cost_accumulated_usd"]

    print(f"Governor state : {STATE_FILE}")
    print(f"Accumulated    : ${accumulated:.4f}")
    print(f"Cap            : {'uncalibrated' if cap <= 0 else f'${cap:.2f}'}")
    if cap > 0:
        pct = accumulated / cap
        hold = ""
        if pct >= 0.90 and mins_remaining > 20:
            hold = " → HOLD (90% threshold)"
        elif pct >= 0.75 and mins_remaining > 60:
            hold = " → HOLD (75% threshold)"
        print(f"Consumed       : {pct:.1%}{hold}")
    print(f"Window resets  : {mins_remaining:.0f}m from now")
    print(f"Last updated   : {state.get('last_updated', 'unknown')}")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)

    if sys.argv[1] == "--status":
        print_status()
    else:
        try:
            cost = float(sys.argv[1])
        except ValueError:
            print(f"Error: expected cost_usd float, got: {sys.argv[1]}", file=sys.stderr)
            sys.exit(1)
        update_cost(cost)
