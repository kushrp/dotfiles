#!/usr/bin/env python3
"""Idempotently wire ~/.claude/settings.json for this dotfiles setup.

Sets the statusLine and the cc-status.sh agent-state hooks, WITHOUT clobbering
any other hooks the user has. Re-runnable: removes our own prior entries
(cc-status.sh / the retired notify-stop.sh) before re-adding, so it converges.

Usage: wire-settings.py [path-to-settings.json]   (default: ~/.claude/settings.json)
"""
import json
import os
import sys

SETTINGS = os.path.expanduser(sys.argv[1] if len(sys.argv) > 1 else "~/.claude/settings.json")
STATUSLINE = "~/.claude/statusline.sh"
HOOK = "~/.claude/hooks/cc-status.sh"
RETIRED = "~/.claude/hooks/notify-stop.sh"

# event -> argument passed to cc-status.sh
EVENTS = {
    "SessionStart": "working",
    "UserPromptSubmit": "working",
    "Notification": "waiting",
    "Stop": "done",
    "SessionEnd": "clear",
}


def load() -> dict:
    try:
        with open(SETTINGS) as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        return {}


def is_ours(cmd: str) -> bool:
    return HOOK in cmd or RETIRED in cmd


def main() -> int:
    d = load()
    d["statusLine"] = {"type": "command", "command": STATUSLINE}
    hooks = d.setdefault("hooks", {})

    for event, arg in EVENTS.items():
        blocks = hooks.get(event, [])
        # Drop our own previous entries from each block; keep everything else.
        cleaned = []
        for blk in blocks:
            kept = [h for h in blk.get("hooks", []) if not is_ours(h.get("command", ""))]
            if kept:
                blk["hooks"] = kept
                cleaned.append(blk)
        # Append our fresh entry for this event.
        cleaned.append({"hooks": [{"type": "command", "command": f"{HOOK} {arg}"}]})
        hooks[event] = cleaned

    os.makedirs(os.path.dirname(SETTINGS), exist_ok=True)
    with open(SETTINGS, "w") as f:
        json.dump(d, f, indent=2)
        f.write("\n")
    print(f"wired statusLine + {len(EVENTS)} cc-status hooks → {SETTINGS}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
