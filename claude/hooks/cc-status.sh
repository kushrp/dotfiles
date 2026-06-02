#!/usr/bin/env bash
# Claude Code agent status → tmux + desktop. Wired (via wire-settings.py) to:
#   SessionStart, UserPromptSubmit → working    (🤖)
#   Notification (permission/idle) → waiting     (⏸  needs you)
#   Stop                           → done        (✅ turn finished)
#   SessionEnd                     → clear
#
# Sets a per-window tmux option @cc_status that the status bar + cc-dashboard
# read, and fires a desktop notification when an agent needs you / finishes.
#
# CRITICAL: never write to stdout — some hook events (UserPromptSubmit) inject
# a hook's stdout into the model's context. We only touch tmux + terminal-notifier.
state="${1:-working}"
input="$(cat 2>/dev/null)"   # consume the hook JSON on stdin

cwd="$(printf '%s' "$input" | jq -r '.cwd // .workspace.current_dir // empty' 2>/dev/null)"
[ -n "$cwd" ] || cwd="$PWD"
proj="${cwd##*/}"

# Per-window status flag (only meaningful inside tmux).
if [ -n "$TMUX" ]; then
  if [ "$state" = "clear" ]; then
    tmux set-option -uw @cc_status 2>/dev/null
  else
    tmux set-option -w @cc_status "$state" 2>/dev/null
  fi
  tmux refresh-client -S 2>/dev/null   # repaint the status bar now
fi

# Desktop notification only for the states that want your attention.
note=""
case "$state" in
  waiting) note="needs your input" ;;
  done)    note="finished" ;;
esac
if [ -n "$note" ] && command -v terminal-notifier >/dev/null 2>&1; then
  terminal-notifier -title "Claude · $proj" -message "$note" \
    -sound Glass -group "claude-$proj" >/dev/null 2>&1
fi
exit 0
