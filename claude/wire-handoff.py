#!/usr/bin/env python3
"""Idempotently wire the token-threshold handoff hooks into settings.json.

Adds a Stop hook (detect threshold → block + instruct handoff) and a
SessionStart/"clear" hook (re-inject the handoff into the fresh context),
WITHOUT clobbering other hooks. Kept separate from wire-settings.py so the
handoff workflow and the status-line tooling stay independent. Re-runnable.

Usage: wire-handoff.py [path-to-settings.json]   (default: ~/.claude/settings.json)
"""
import json
import os
import sys

SETTINGS = os.path.expanduser(sys.argv[1] if len(sys.argv) > 1 else "~/.claude/settings.json")

STOP_CMD = "~/.claude/hooks/handoff-threshold-stop.py"
START_CMD = "~/.claude/hooks/handoff-sessionstart.py"
MARKERS = ("handoff-threshold-stop.py", "handoff-sessionstart.py")


def is_ours(cmd: str) -> bool:
    return any(m in cmd for m in MARKERS)


def strip_ours(blocks: list) -> list:
    """Drop our own hook commands from each block; keep all other hooks/blocks."""
    cleaned = []
    for blk in blocks:
        kept = [h for h in blk.get("hooks", []) if not is_ours(h.get("command", ""))]
        if kept:
            blk["hooks"] = kept
            cleaned.append(blk)
        elif not blk.get("hooks") and any(k != "hooks" for k in blk):
            cleaned.append(blk)  # preserve odd blocks that carry only a matcher
    return cleaned


def main() -> int:
    try:
        with open(SETTINGS) as f:
            d = json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        d = {}

    hooks = d.setdefault("hooks", {})

    hooks["Stop"] = strip_ours(hooks.get("Stop", [])) + [
        {"hooks": [{"type": "command", "command": STOP_CMD}]}
    ]
    hooks["SessionStart"] = strip_ours(hooks.get("SessionStart", [])) + [
        {"matcher": "clear", "hooks": [{"type": "command", "command": START_CMD}]}
    ]

    os.makedirs(os.path.dirname(SETTINGS), exist_ok=True)
    with open(SETTINGS, "w") as f:
        json.dump(d, f, indent=2)
        f.write("\n")
    print(f"wired handoff Stop + SessionStart(clear) hooks → {SETTINGS}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
