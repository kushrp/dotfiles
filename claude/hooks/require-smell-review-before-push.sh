#!/bin/bash
# PreToolUse gate: block git push / gt submit / gt create until the
# rogo-ts-effect-reviewer agent has reviewed the current HEAD and returned PASS.
# The deny reason tells Claude to dispatch that reviewer (it reads the live
# ts-code-smells / rogo-self-review rulebooks), and only after a PASS verdict to
# touch a per-commit marker so the retried push goes through. New commits
# invalidate the marker, so every push of new code gets a fresh review.

# Fail-open: any internal error → exit 0 silently (never strand a push on a broken hook).
set -uo pipefail

INPUT=$(cat)

COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
[ -z "$COMMAND" ] && exit 0

if ! echo "$COMMAND" | grep -qE '(^|[;&|[:space:]])(git push|gt (submit|create|ss|s|c)\b)'; then
  exit 0
fi

# Intermediate babysitting pushes (draft updates while a stack is being watched
# to readiness) skip the gate; only the final publish-ready push gets reviewed.
if echo "$COMMAND" | grep -qE -- '--update-only|--draft'; then
  exit 0
fi

CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
[ -z "$CWD" ] && CWD="${CLAUDE_PROJECT_DIR:-$(pwd)}"

HEAD_SHA=$(git -C "$CWD" rev-parse HEAD 2>/dev/null) || exit 0
MARKER="${TMPDIR:-/tmp}/claude-smell-review-ok-${HEAD_SHA}"

[ -f "$MARKER" ] && exit 0

jq -n --arg marker "$MARKER" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: ("Pre-push gate (HARD): every push goes through the rogo-ts-effect-reviewer agent first. Dispatch it now (Agent tool, subagent_type \"rogo-ts-effect-reviewer\") over the diff this push introduces — it reads the live ts-code-smells / rogo-self-review rulebooks and returns VERDICT: PASS | BLOCK. If BLOCK: fix every blocking finding at the source and re-dispatch until PASS (do NOT touch the marker to bypass a BLOCK). Only after a PASS verdict, in a SEPARATE Bash call (the gate denies any command string containing the push), run: touch \($marker) — then retry this exact push command. New commits require a fresh PASS.")
  }
}'

exit 0
