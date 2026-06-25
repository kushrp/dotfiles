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
# Claude session id + transcript path, so agent-slack can map THIS pane to its
# exact transcript (panes often share a cwd, so cwd alone is ambiguous).
session="$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)"
transcript="$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null)"

# Per-PANE status flag (only meaningful inside tmux). Pane-scoped, not
# window-scoped: several agents commonly run as split panes in one window, and a
# window option would let them clobber each other (and inheritance would make
# unset panes read a sibling's value). cc-agent-count / cc-dashboard read this
# per pane. The default target pane comes from $TMUX_PANE, set by the hook's
# parent (claude), so no -t is needed.
if [ -n "$TMUX" ] && [ -n "$TMUX_PANE" ]; then
  # CRITICAL: target $TMUX_PANE explicitly. `set-option -p` WITHOUT -t resolves to
  # the server's ACTIVE pane, not this agent's pane — so when a background agent
  # fires a hook while you're focused elsewhere, its state lands on the wrong
  # pane. -t "$P" pins every write to the agent that actually fired the hook.
  P="$TMUX_PANE"
  if [ "$state" = "clear" ]; then
    tmux set-option -up -t "$P" @cc_status 2>/dev/null
  else
    tmux set-option -p -t "$P" @cc_status "$state" 2>/dev/null
  fi
  # Stamp this pane's Claude session id + transcript path so agent-slack can map
  # the exact pane to its transcript (panes often share a cwd, so cwd is not
  # enough). Set on every hook fire so it stays current across resumes.
  [ -n "$session" ]    && tmux set-option -p -t "$P" @cc_session "$session" 2>/dev/null
  [ -n "$transcript" ] && tmux set-option -p -t "$P" @cc_transcript "$transcript" 2>/dev/null
  # Stamp when a pane ENTERS waiting so the bar can show how long it's been
  # blocked (oldest-wait timer); clear the stamp on any other state.
  if [ "$state" = "waiting" ]; then
    tmux set-option -p -t "$P" @cc_waiting_since "$(date +%s)" 2>/dev/null
  else
    tmux set-option -up -t "$P" @cc_waiting_since 2>/dev/null
  fi
  # Roll this window's tab glyph up to its neediest pane (waiting > working >
  # done). Kept under a SEPARATE name (@cc_win) so it never leaks into the
  # per-pane @cc_status reads via tmux option inheritance.
  win="$(tmux display-message -p -t "$P" '#{window_id}' 2>/dev/null)"
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

# Attention routing for the states that want you. cc-notify fans out to desktop
# (always) + phone/Slack (per its config), throttled, and carries the agent's
# tmux target so a future reply-listener can route a response back. Fail-open:
# if cc-notify is missing, fall back to a plain desktop notification.
note=""
case "$state" in
  waiting) note="needs your input" ;;
  done)    note="finished" ;;
esac
if [ -n "$note" ]; then
  if command -v cc-notify >/dev/null 2>&1; then
    cc-notify --state "$state" --title "Claude · $proj" --message "$note" \
      --proj "$proj" --pane "${TMUX_PANE:-}" >/dev/null 2>&1
  elif command -v terminal-notifier >/dev/null 2>&1; then
    terminal-notifier -title "Claude · $proj" -message "$note" \
      -sound Glass -group "claude-$proj" >/dev/null 2>&1
  fi
fi
exit 0
