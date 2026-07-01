#!/usr/bin/env bash
# Set a per-pane tmux user option @cc_work to a short label for the work in this
# pane (Linear ticket > PR number > git branch), so the pane border shows what
# each Claude session is doing. Safe no-op outside tmux.
#
# Called automatically by Claude Code SessionStart/UserPromptSubmit hooks, and
# manually via the /pane slash command or directly:
#   cc-tmux-pane-title.sh            # auto-derive (respects a manual override)
#   cc-tmux-pane-title.sh "AGE-400"  # pin a manual label
#   cc-tmux-pane-title.sh auto       # clear the manual override, re-derive
set -euo pipefail

# Linear team prefixes used to spot a ticket in a branch/PR title. Extend freely.
TICKET_PREFIXES="AGE|ROGO|ENG|DATA|SEC|INFRA|PLAT|QUAL"
PR_CACHE_TTL_MIN=10
MAX_LEN=44

[ -n "${TMUX:-}" ] || exit 0
pane="${TMUX_PANE:-$(tmux display -p '#{pane_id}' 2>/dev/null || true)}"
[ -n "$pane" ] || exit 0

arg="${1:-}"

set_label() { tmux set -p -t "$pane" @cc_work "$1"; }

case "$arg" in
  auto)
    tmux set -pu -t "$pane" @cc_work_override 2>/dev/null || true
    ;;
  "")
    # No arg: a manual override wins and the hook must not clobber it.
    override="$(tmux show -pqv -t "$pane" @cc_work_override 2>/dev/null || true)"
    if [ -n "$override" ]; then
      set_label "$override"
      exit 0
    fi
    ;;
  *)
    # Pin a manual label.
    tmux set -p -t "$pane" @cc_work_override "$arg"
    set_label "$arg"
    exit 0
    ;;
esac

# Resolve the repo dir: hook env, else hook stdin JSON, else PWD.
cwd="${CLAUDE_PROJECT_DIR:-}"
if [ -z "$cwd" ] && [ ! -t 0 ]; then
  stdin_json="$(cat 2>/dev/null || true)"
  [ -n "$stdin_json" ] && cwd="$(printf '%s' "$stdin_json" | jq -r '.cwd // empty' 2>/dev/null || true)"
fi
[ -n "$cwd" ] || cwd="$PWD"

branch="$(git -C "$cwd" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
if [ -z "$branch" ] || [ "$branch" = "HEAD" ]; then
  set_label ""
  exit 0
fi
short="${branch#*/}" # drop a leading "user/" prefix

# Cached PR lookup (number + title), keyed by repo + branch.
toplevel="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null || echo "$cwd")"
# shellcheck disable=SC2046
set -- $(printf '%s' "$toplevel|$branch" | cksum)
cache="${TMPDIR:-/tmp}/cc-pane-pr.$1"
[ "$arg" = "auto" ] && rm -f "$cache"
if [ -z "$(find "$cache" -mmin "-$PR_CACHE_TTL_MIN" 2>/dev/null)" ]; then
  (cd "$cwd" && gh pr view --json number,title -q '[.number,.title]|@tsv') >"$cache" 2>/dev/null || : >"$cache"
fi
pr_line="$(cat "$cache" 2>/dev/null || true)"
pr_num="$(printf '%s' "$pr_line" | cut -f1)"
pr_title="$(printf '%s' "$pr_line" | cut -f2-)"

ticket="$(printf '%s\n%s\n' "$branch" "$pr_title" | grep -oiE "(${TICKET_PREFIXES})-[0-9]+" | head -1 | tr '[:lower:]' '[:upper:]' || true)"

if [ -n "$ticket" ]; then
  label="$ticket $short"
elif [ -n "$pr_num" ]; then
  label="#$pr_num $short"
else
  label="$short"
fi

[ "${#label}" -gt "$MAX_LEN" ] && label="${label:0:$((MAX_LEN - 1))}…"

set_label "$label"
