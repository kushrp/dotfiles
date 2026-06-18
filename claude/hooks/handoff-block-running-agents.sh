#!/usr/bin/env bash
# Stop + PreCompact hook: never hand off / compact while background subagents or
# background bash tasks for THIS session are still running.
#
# Why this exists (Kush, 2026-06-16): a prior incarnation crossed the token
# threshold, auto-summarised into a handoff doc and /cleared *while a background
# code-review agent was still running* — its findings were never relayed and
# nearly lost. The requirement: a handoff/compaction must NOT proceed while any
# background task for the session is in flight, and the agent must integrate
# every completed subagent's results into the handoff doc first.
#
# Two events wired to one script (it self-detects which):
#   Stop       — hard-blocks the turn from ending (decision:"block"). This is the
#                real gate: Kush's handoff is driven by handoff-threshold-stop.py,
#                also a Stop hook, so blocking the Stop blocks the handoff. Stop
#                hooks CAN hard-block; this composes with the threshold hook (any
#                Stop hook's block wins).
#   PreCompact — native auto-compaction can't be hard-cancelled by a hook, so
#                here we emit the strongest available signal: additionalContext +
#                systemMessage telling the model agents are still running and
#                their output must be integrated before any handoff. Best-effort
#                belt-and-braces in case native compaction ever fires first.
#
# RUNNING detection (verified on-disk 2026-06-16): background tasks for a session
# live at  $TMPDIR-ish/claude-<uid>/<cwd-slug>/<session-id>/tasks/<task-id>.output
# where the cwd-slug is the cwd with every "/" replaced by "-". A subagent's
# .output is a symlink to its subagents/agent-*.jsonl; a background bash task's is
# a regular file of live stdout. There is NO status/lock/pid/exit file. The
# authoritative "still running" signal is therefore: some live process holds the
# .output open FOR WRITE (lsof). A finished task has no writer. We exclude the
# hook's own process group (the hook itself runs as a transient bash task that
# writes its own .output — without this guard it would see itself and deadlock).
#
# FAIL-SAFE: this gate must never permanently brick handoffs. If we cannot
# determine state (no lsof, no tasks dir, malformed stdin, any error) we FAIL
# OPEN — exit 0, allow the stop/compaction. We only ever block when we can
# positively see >=1 running task that is not us. A stuck background task is
# escapable: disable via the env toggle below, or just answer the model's prompt.
#
# DISABLE: export HANDOFF_BLOCK_RUNNING_AGENTS=0  (env in ~/.claude/settings.json
# or your shell). Any value other than "0"/"false"/"no" leaves it enabled.
# You can also remove the two registrations in ~/.claude/settings.json.

set -uo pipefail

# --- toggle ---------------------------------------------------------------
toggle="${HANDOFF_BLOCK_RUNNING_AGENTS:-1}"
case "$toggle" in
  0|false|no|off|FALSE|NO|OFF) exit 0 ;;
esac

# --- read hook stdin (guard malformed/empty) ------------------------------
input="$(cat 2>/dev/null || true)"
[ -n "$input" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0   # no jq → can't parse → fail open

event="$(printf '%s' "$input" | jq -r '.hook_event_name // empty' 2>/dev/null)"
session_id="$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)"
cwd="$(printf '%s' "$input" | jq -r '.cwd // .workspace.current_dir // empty' 2>/dev/null)"
[ -n "$cwd" ] || cwd="$PWD"
[ -n "$session_id" ] || exit 0   # can't locate the session's tasks dir → fail open

# --- locate this session's tasks dir --------------------------------------
# slug = cwd with every "/" -> "-" (leading "/" becomes leading "-").
slug="$(printf '%s' "$cwd" | sed 's#/#-#g')"
uid="$(id -u)"
tasks_dir=""
for base in "/private/tmp/claude-$uid" "/tmp/claude-$uid" "${TMPDIR:-/tmp}/claude-$uid"; do
  cand="$base/$slug/$session_id/tasks"
  if [ -d "$cand" ]; then tasks_dir="$cand"; break; fi
done
[ -n "$tasks_dir" ] || exit 0   # no tasks dir → nothing ever ran → fail open

command -v lsof >/dev/null 2>&1 || exit 0  # no lsof → can't detect → fail open

# --- find running tasks (open-for-write .output), excluding ourselves -----
# Our own process group: the hook + all its pipeline/subshell children share it,
# while genuine background tasks (spawned by the main `claude` process) do not.
my_pgid="$(ps -o pgid= -p "$$" 2>/dev/null | tr -d ' ')"

# lsof +D walks the dir. FD column (field 4) like "12w"/"3u" = open for write.
# We collect "pid<TAB>path" for every write handle on a *.output, then drop any
# pid in our own process group, and de-dupe by task file.
running="$(
  lsof -w +D "$tasks_dir" 2>/dev/null \
    | awk '$4 ~ /[0-9]+[wuWU]/ && $NF ~ /\.output$/ { print $2"\t"$NF }' \
    | while IFS=$'\t' read -r pid path; do
        pgid="$(ps -o pgid= -p "$pid" 2>/dev/null | tr -d ' ')"
        [ -n "$pgid" ] && [ "$pgid" = "$my_pgid" ] && continue   # skip self
        printf '%s\n' "$path"
      done \
    | sort -u
)"

[ -n "$running" ] || exit 0   # no foreign writers → all agents done → allow

# --- build the human-readable list of running task ids --------------------
ids="$(printf '%s\n' "$running" | sed 's#.*/##; s#\.output$##' | paste -sd, - 2>/dev/null)"
count="$(printf '%s\n' "$running" | grep -c . 2>/dev/null)"
[ -n "$count" ] || count="?"

msg="Handoff/compaction blocked: ${count} background agent(s)/task(s) still running for this session (${ids}). \
Do NOT hand off, compact, or /clear yet. Wait for every background subagent and background task to finish, \
then integrate each one's results into the handoff doc before writing it — never lose subagent context. \
Check progress with the agent dashboard or by re-reading their output; once they have all completed and \
their findings are captured, you may proceed. (To disable this gate: set HANDOFF_BLOCK_RUNNING_AGENTS=0.)"

# --- emit the right contract for the event --------------------------------
if [ "$event" = "PreCompact" ]; then
  # Native auto-compaction cannot be hard-cancelled by a hook. Emit the loudest
  # signal we can: a user-visible systemMessage + additionalContext injected into
  # the model's context so the handoff it writes accounts for the running agents.
  jq -n --arg m "$msg" '{
    systemMessage: $m,
    hookSpecificOutput: { hookEventName: "PreCompact", additionalContext: $m }
  }'
  exit 0
fi

# Default = Stop (the real gate). decision:"block" hard-blocks the turn from
# ending, which blocks the handoff-threshold-stop.py handoff and any manual stop.
jq -n --arg m "$msg" '{
  decision: "block",
  reason: $m,
  hookSpecificOutput: { hookEventName: "Stop", additionalContext: $m }
}'
exit 0
