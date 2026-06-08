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

# Per-PANE status flag (only meaningful inside tmux). Pane-scoped, not
# window-scoped: several agents commonly run as split panes in one window, and a
# window option would let them clobber each other (and inheritance would make
# unset panes read a sibling's value). cc-agent-count / cc-dashboard read this
# per pane. The default target pane comes from $TMUX_PANE, set by the hook's
# parent (claude), so no -t is needed.
if [ -n "$TMUX" ]; then
  if [ "$state" = "clear" ]; then
    tmux set-option -up @cc_status 2>/dev/null
  else
    tmux set-option -p @cc_status "$state" 2>/dev/null
  fi
  # Roll this window's tab glyph up to its neediest pane (waiting > working >
  # done). Kept under a SEPARATE name (@cc_win) so it never leaks into the
  # per-pane @cc_status reads via tmux option inheritance.
  win="$(tmux display-message -p '#{window_id}' 2>/dev/null)"
  if [ -n "$win" ]; then
    roll=""
    for s in waiting working "done"; do
      if tmux list-panes -t "$win" -F '#{@cc_status}' 2>/dev/null | grep -qx "$s"; then
        roll="$s"; break
      fi
    done
    if [ -n "$roll" ]; then
      tmux set-option -w -t "$win" @cc_win "$roll" 2>/dev/null
    else
      tmux set-option -uw -t "$win" @cc_win 2>/dev/null
    fi
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
