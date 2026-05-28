#!/usr/bin/env zsh
# Login shells: keep this minimal. The heavy lifting (PATH, completion,
# tool init) lives in .zshrc so it also fires for interactive non-login
# shells (e.g. tmux panes, Ghostty windows after the first).
#
# We still set Homebrew shellenv here so that GUI-launched login shells
# (some IDEs, scripts) see /opt/homebrew on PATH even if they don't read
# .zshrc.

if [[ -x /opt/homebrew/bin/brew ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
elif [[ -x /usr/local/bin/brew ]]; then
  eval "$(/usr/local/bin/brew shellenv)"
fi
