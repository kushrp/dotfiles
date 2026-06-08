#!/usr/bin/env python3
"""Stop hook: at a context-token threshold, force a clean handoff.

When the live context window crosses HANDOFF_TOKEN_THRESHOLD (default 250k),
block the turn from ending and instruct the model to write a thorough handoff
doc, then ask the user to /clear. A sibling SessionStart hook
(handoff-sessionstart.py) re-injects that doc into the fresh context.

Why a Stop hook and not PreCompact: there is no hook input exposing live token
count, and no setting to tune native auto-compaction. But the transcript JSONL
records each assistant turn's usage, whose sum (input + cache_creation +
cache_read) IS the current context size. We read that and act *before* native
compaction would. Only the model can write the summary, so the hook's job is
purely to detect the threshold and hand the model its instructions.

Loop-safety: a per-session marker (.pending-<id>) is dropped on first trigger;
while it exists the hook stays out of the way so the handoff turn itself, and
any further chatter, can stop normally.
"""
import glob
import json
import os
import subprocess
import sys

THRESHOLD = int(os.environ.get("HANDOFF_TOKEN_THRESHOLD", "250000"))


def resolve_handoff_dir(cwd: str) -> str:
    """One handoff store per repo, shared across all worktrees.

    `git rev-parse --git-common-dir` resolves to the *shared* .git from every
    linked worktree (e.g. .../repo/.git from both repo/ and repo-worktrees/x),
    so a handoff written in one worktree is found when /clear happens in another.
    Its parent is the primary worktree root → store under <root>/.claude/handoffs.
    Falls back to <cwd>/.claude/handoffs outside a git repo.
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


def current_context_tokens(path: str) -> int:
    """Tokens occupying the context window now = the most recent assistant
    turn's input + cache_creation + cache_read usage."""
    if not path or not os.path.exists(path):
        return 0
    latest = 0
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
            except json.JSONDecodeError:
                continue
            msg = obj.get("message")
            usage = msg.get("usage") if isinstance(msg, dict) else None
            if usage is None:
                usage = obj.get("usage")
            if isinstance(usage, dict):
                total = (
                    usage.get("input_tokens", 0)
                    + usage.get("cache_creation_input_tokens", 0)
                    + usage.get("cache_read_input_tokens", 0)
                )
                if total:
                    latest = total
    return latest


def handoff_instructions(path: str, tokens: int) -> str:
    return f"""\
HANDOFF THRESHOLD REACHED (~{tokens:,} tokens in context, limit {THRESHOLD:,}).

Before you stop, do exactly this and nothing else:

1. Invoke the `handoff` skill (Skill tool, skill="handoff") to compact this
   conversation into a handoff document. In its `args`, instruct it to:
   - cover ALL active threads of this session for a fresh agent with ZERO prior
     context (goal, current state, ordered next steps, key files as path:line,
     decisions + rationale, gotchas/constraints, commands, open questions);
   - SAVE the finished handoff document to this exact path (create parent dirs):
       {path}

2. Confirm the file exists at that path. If the skill returned the document as
   text instead of writing it, write it there yourself — this path is the
   contract the SessionStart hook reads on /clear, so the file MUST be present.

3. Then tell the user, verbatim:
   "Handoff written. Run /clear to continue in a fresh context window — I'll be briefed automatically."

Do not pick up other work in this turn."""


def main() -> int:
    data = json.load(sys.stdin)
    session_id = data.get("session_id", "unknown")
    transcript = data.get("transcript_path", "")
    cwd = data.get("cwd") or os.getcwd()

    handoff_dir = resolve_handoff_dir(cwd)
    marker = os.path.join(handoff_dir, f".pending-{session_id}")

    # Already handed off this session → let the turn end normally.
    if os.path.exists(marker):
        return 0

    if current_context_tokens(transcript) < THRESHOLD:
        return 0

    tokens = current_context_tokens(transcript)
    os.makedirs(handoff_dir, exist_ok=True)
    with open(marker, "w") as f:
        f.write(str(tokens))

    handoff_path = os.path.join(handoff_dir, f"{session_id}.md")
    print(
        json.dumps(
            {
                "decision": "block",
                "reason": handoff_instructions(handoff_path, tokens),
                "hookSpecificOutput": {
                    "hookEventName": "Stop",
                    "additionalContext": handoff_instructions(handoff_path, tokens),
                },
            }
        )
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
