#!/usr/bin/env python3
import json
import sys
import os
from datetime import datetime, timedelta

STATE_FILE = ".syndicate/usage_state.json"

def update_usage(tokens_used):
    if not os.path.exists(STATE_FILE):
        print("[@gavel] [ERROR] usage_state.json missing. Cannot update.")
        sys.exit(1)

    with open(STATE_FILE, 'r+') as f:
        data = json.load(f)
        
        # Update metrics
        data["estimated_tokens_consumed"] += tokens_used
        data["remaining_buffer"] -= tokens_used
        data["last_action"] = "API_DISPATCH_SUCCESS"
        
        # Basic reset logic: if 5 hours have passed, reset the buffer
        start_time = datetime.fromisoformat(data["session_start_utc"].replace("Z", ""))
        if datetime.utcnow() > start_time + timedelta(hours=5):
            data["session_start_utc"] = datetime.utcnow().isoformat() + "Z"
            data["estimated_tokens_consumed"] = tokens_used
            data["remaining_buffer"] = 40000 - tokens_used
            data["quota_reset_estimated_utc"] = (datetime.utcnow() + timedelta(hours=5)).isoformat() + "Z"

        f.seek(0)
        json.dump(data, f, indent=2)
        f.truncate()

if __name__ == "__main__":
    if len(sys.argv) > 1:
        update_usage(int(sys.argv[1]))
    else:
        print("Usage: python3 update_usage.py <token_count>")
