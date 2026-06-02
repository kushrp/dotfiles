#!/usr/bin/env bash
# Claude Code Stop hook: ping me when a run finishes while I'm looking elsewhere
# (another tmux pane/window, another app). Wired via ~/.claude/settings.json.
#
# - tmux: flag the window (monitor-bell in .tmux.conf surfaces it in the status bar)
# - macOS: a notification + subtle sound via terminal-notifier (fallback osascript)
# - terminal bell as a last resort
#
# Reads the hook JSON on stdin; pulls the cwd for a useful message.
set -o pipefail
input="$(cat 2>/dev/null)"
dir="$(printf '%s' "$input" | jq -r '.cwd // .workspace.current_dir // empty' 2>/dev/null)"
[ -n "$dir" ] && dir="${dir/#$HOME/~}" || dir="$(pwd)"
proj="${dir##*/}"
msg="finished in ${proj}"

# tmux: ring the bell on this pane (status bar flags it if you're elsewhere).
if [ -n "$TMUX" ]; then
  printf '\a'                                   # bell → monitor-bell catches it
  tmux display-message -d 1500 "✅ Claude $msg" 2>/dev/null
fi

# macOS desktop notification.
if command -v terminal-notifier >/dev/null 2>&1; then
  terminal-notifier -title "Claude Code" -subtitle "$proj" -message "Run finished" \
    -sound Glass -group "claude-$proj" >/dev/null 2>&1
elif command -v osascript >/dev/null 2>&1; then
  osascript -e "display notification \"Run finished\" with title \"Claude Code\" subtitle \"$proj\" sound name \"Glass\"" >/dev/null 2>&1
else
  printf '\a'
fi
exit 0
