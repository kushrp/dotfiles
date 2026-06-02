#!/usr/bin/env bash
# Claude Code statusline. Wired via ~/.claude/settings.json "statusLine".
# Claude pipes a JSON blob on stdin; we render:
#   <model> · <dir> · <git branch+dirty> · +adds/-dels · $cost · ⏱duration
# Tokyo Night ANSI colors. Pure bash + jq; degrades if a field is absent.
set -o pipefail
input="$(cat)"

j() { printf '%s' "$input" | jq -r "$1" 2>/dev/null; }

model="$(j '.model.display_name')"
cur="$(j '.workspace.current_dir')"
adds="$(j '.cost.total_lines_added // 0')"
dels="$(j '.cost.total_lines_removed // 0')"
cost="$(j '.cost.total_cost_usd // 0')"
dur_ms="$(j '.cost.total_duration_ms // 0')"
over200k="$(j '.exceeds_200k_tokens // false')"

# Tokyo Night palette via 24-bit ANSI.
c_reset=$'\e[0m'; c_blue=$'\e[38;2;122;162;247m'; c_cyan=$'\e[38;2;125;207;255m'
c_mag=$'\e[38;2;187;154;247m'; c_green=$'\e[38;2;158;206;106m'; c_red=$'\e[38;2;247;118;142m'
c_yellow=$'\e[38;2;224;175;104m'; c_dim=$'\e[38;2;86;95;137m'

# Directory: basename, ~ for home.
dir_disp="${cur/#$HOME/~}"; dir_disp="${dir_disp##*/}"
[ -z "$dir_disp" ] && dir_disp="~"

# Git branch + dirty flag (cheap; runs in $cur).
branch=""
if git -C "$cur" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  branch="$(git -C "$cur" symbolic-ref --quiet --short HEAD 2>/dev/null \
            || git -C "$cur" rev-parse --short HEAD 2>/dev/null)"
  git -C "$cur" diff --quiet --ignore-submodules HEAD 2>/dev/null || branch="${branch}*"
fi

out="${c_mag}${model}${c_reset}"
out+=" ${c_dim}·${c_reset} ${c_blue}${dir_disp}${c_reset}"
[ -n "$branch" ] && out+=" ${c_dim}·${c_reset} ${c_cyan} ${branch}${c_reset}"
if [ "$adds" != "0" ] || [ "$dels" != "0" ]; then
  out+=" ${c_dim}·${c_reset} ${c_green}+${adds}${c_reset}/${c_red}-${dels}${c_reset}"
fi
# Cost (only once non-zero), formatted to cents.
if [ "$cost" != "0" ] && [ "$cost" != "null" ]; then
  out+=" ${c_dim}·${c_reset} ${c_yellow}\$$(printf '%.2f' "$cost")${c_reset}"
fi
# Duration in a friendly unit.
if [ "$dur_ms" != "0" ] && [ "$dur_ms" != "null" ]; then
  secs=$(( dur_ms / 1000 ))
  if (( secs >= 60 )); then dur="$(( secs / 60 ))m$(( secs % 60 ))s"; else dur="${secs}s"; fi
  out+=" ${c_dim}·${c_reset} ${c_dim}⏱${dur}${c_reset}"
fi
[ "$over200k" = "true" ] && out+=" ${c_red}⚠ >200k ctx${c_reset}"

printf '%s' "$out"
