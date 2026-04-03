#!/usr/bin/env python3
import json
import os
import subprocess
import sys

# SYNDICATE GOVERNANCE CONFIG
TOKEN_LIMIT = 30000
BUFFER_THRESHOLD = 5000
STATE_FILE = "usage_state.json"

def get_staged_diff_size():
    try:
        # Measure the character weight of staged changes
        diff_proc = subprocess.run(['git', 'diff', '--cached'], capture_output=True, text=True)
        return len(diff_proc.stdout)
    except Exception:
        return 0

def audit_resource_gate():
    if not os.path.exists(STATE_FILE):
        # Initialize if missing - Consigliere's Default
        initial_state = {"remaining_buffer": 40000, "estimated_tokens_consumed": 0}
        os.makedirs(os.path.dirname(STATE_FILE), exist_ok=True)
        with open(STATE_FILE, 'w') as f:
            json.dump(initial_state, f)
        return True, 0

    with open(STATE_FILE, 'r') as f:
        state = json.load(f)
    
    chars = get_staged_diff_size()
    est_tokens = chars // 4  # Standard Syndicate heuristic
    remaining = state.get("remaining_buffer", 0)

    # REFUSAL_CONDITION_3: Quota Depleted
    if remaining < BUFFER_THRESHOLD:
        print(f"[@gavel] [BLOCK] Quota Depleted: {remaining} < {BUFFER_THRESHOLD}")
        return False, est_tokens
    
    # REFUSAL_CONDITION_5: Context Overflow
    if est_tokens > TOKEN_LIMIT:
        print(f"[@gavel] [BLOCK] Context Overflow: {est_tokens} > {TOKEN_LIMIT}")
        return False, est_tokens

    return True, est_tokens

if __name__ == "__main__":
    passed, tokens = audit_resource_gate()
    if passed:
        print(f"[@gavel] [PASS] Resource Audit: ~{tokens} tokens. Budget Clear.")
        sys.exit(0)
    else:
        sys.exit(1)
