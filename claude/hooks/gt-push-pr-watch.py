#!/usr/bin/env python3
"""PostToolUse hook: after a successful `gt ss` / `gt submit` push, remind the
agent to run the gt-pr-watch skill so PR review comments keep getting tracked."""
import json
import re
import sys

try:
    payload = json.load(sys.stdin)
except json.JSONDecodeError:
    sys.exit(0)

command = (payload.get("tool_input") or {}).get("command", "")
if not re.search(r"\bgt\s+(ss|submit)\b", command):
    sys.exit(0)

# Skip intermediate draft updates while a stack is being babysat to readiness;
# only remind on the final publish-ready push (Kush, 2026-06-12).
if re.search(r"--update-only|--draft", command):
    sys.exit(0)

output = {
    "hookSpecificOutput": {
        "hookEventName": "PostToolUse",
        "additionalContext": (
            "A `gt submit` push just ran. Per Kush's standing instruction, keep "
            "tracking the pushed PRs for review comments: invoke the `gt-pr-watch` "
            "skill (sweep unresolved threads, fix or reply+resolve bot comments, "
            "draft replies for human comments — never reply to humans directly), "
            "unless a gt-pr-watch sweep already ran in the last few minutes."
        ),
    }
}
print(json.dumps(output))
