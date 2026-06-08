#!/usr/bin/env python3
"""SessionStart hook (wired for the "clear" source): brief a fresh context.

After a handoff-triggered /clear, load the newest handoff doc and inject it into
the new context. Looks in the repo-shared handoff store first (one per repo,
shared across worktrees — see resolve_handoff_dir), then falls back to the OS
temp dir, because the `handoff` skill's own default is to save there. Consume-
once: the loaded doc is renamed to *.loaded and any stale .pending-* markers are
removed, so re-clearing later does not re-inject an outdated handoff.

Pairs with handoff-threshold-stop.py.
"""
import glob
import json
import os
import subprocess
import sys
import tempfile
import time

TEMP_HANDOFF_MAX_AGE_S = 2 * 86400


def resolve_handoff_dir(cwd: str) -> str:
    """One handoff store per repo, shared across all worktrees.

    `git rev-parse --git-common-dir` resolves to the *shared* .git from every
    linked worktree, so a handoff written in one worktree is found when /clear
    happens in another. Must match handoff-threshold-stop.py's resolver.
    """
    try:
        out = subprocess.run(
            ["git", "-C", cwd, "rev-parse", "--git-common-dir"],
            capture_output=True,
            text=True,
            timeout=5,
        )
        common = out.stdout.strip()
        if out.returncode == 0 and common:
            common = os.path.abspath(os.path.join(cwd, common))
            return os.path.join(os.path.dirname(common), ".claude", "handoffs")
    except Exception:
        pass
    return os.path.join(cwd, ".claude", "handoffs")


def temp_handoff_docs(markers: list) -> list:
    """Recent *handoff*.md files in the OS temp dir(s) that belong to THIS repo.

    The `handoff` skill saves to the OS temp dir by default; pick those up so a
    skill-saved handoff still briefs the next session. Two guards keep this from
    cross-contaminating repos (temp is shared and repo-agnostic): mtime recency,
    and a content check that the doc references one of `markers` (the repo root
    or cwd) — a handoff for another project won't mention this one's path.
    """
    seen_dirs = set()
    cutoff = time.time() - TEMP_HANDOFF_MAX_AGE_S
    found = []
    for d in (os.environ.get("TMPDIR"), tempfile.gettempdir(), "/tmp"):
        if not d or d in seen_dirs:
            continue
        seen_dirs.add(d)
        for path in glob.glob(os.path.join(d, "*[Hh]andoff*.md")):
            try:
                if os.path.getmtime(path) < cutoff:
                    continue
                with open(path) as f:
                    body = f.read()
            except OSError:
                continue
            if any(mark and mark in body for mark in markers):
                found.append(path)
    return found


def main() -> int:
    data = json.load(sys.stdin)
    cwd = data.get("cwd") or os.getcwd()

    handoff_dir = resolve_handoff_dir(cwd)
    docs = glob.glob(os.path.join(handoff_dir, "*.md"))
    if not docs:
        repo_root = os.path.dirname(os.path.dirname(handoff_dir))
        docs = temp_handoff_docs([repo_root, os.path.basename(repo_root), cwd])
    if not docs:
        return 0

    newest = max(docs, key=os.path.getmtime)
    with open(newest) as f:
        content = f.read()

    context = (
        f"A previous session handed off its context. It crossed the token "
        f"threshold, summarized its state into `{os.path.basename(newest)}`, "
        f"and cleared. Pick up exactly where it left off.\n\n"
        f"---\n\n{content}"
    )

    # Consume so future /clear calls start truly fresh.
    os.rename(newest, newest + ".loaded")
    for stale in glob.glob(os.path.join(handoff_dir, ".pending-*")):
        os.remove(stale)

    print(
        json.dumps(
            {
                "hookSpecificOutput": {
                    "hookEventName": "SessionStart",
                    "additionalContext": context,
                }
            }
        )
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
