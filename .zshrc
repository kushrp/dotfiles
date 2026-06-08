#!/usr/bin/env zsh
# Full-stack zsh: fast startup, fuzzy completion, autosuggestions, syntax
# highlighting, starship prompt. Designed to work on a fresh laptop after
# `./install.sh` (which `brew install`s all the dependencies referenced
# here). Every plugin block fails open if its dep isn't present.
#
# Layer order matters:
#   1. Homebrew shellenv (so brew-installed plugins are findable)
#   2. PATH + tool env (nvm, bun)
#   3. Shared dotfiles (.aliases, .functions, .exports, .extra)
#   4. compinit (must happen BEFORE plugins that register completions)
#   5. fzf-tab, zsh-autosuggestions, fast-syntax-highlighting
#      (order: fzf-tab BEFORE autosuggest/highlighter)
#   6. starship + zoxide

# --- 0. init-script cache ---------------------------------------------------
# Tools like starship/mise/zoxide/atuin/direnv emit a static init script that
# we'd normally `eval "$(tool init)"`. Each of those forks a binary at every
# shell start (~30-50ms each = 150-250ms total). Instead we cache the output
# to disk and re-`source` it, regenerating only when the tool binary OR this
# .zshrc is newer than the cache. Cuts warm startup roughly in half.
_ZSH_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/zsh-init"
[[ -d "$_ZSH_CACHE_DIR" ]] || mkdir -p "$_ZSH_CACHE_DIR"

# _cache_init <cache-name> <binary> <args...>
# Runs `<binary> <args...>`, caches stdout, and sources it. Regenerates when
# the binary or ~/.zshrc changes. The cached script is compiled to bytecode
# (.zwc) so sourcing it is a fast mmap instead of a full parse — zsh auto-uses
# <file>.zwc when it's newer than <file>.
_cache_init() {
  local name="$1" bin="$2"; shift
  local cache="$_ZSH_CACHE_DIR/${name}.zsh"
  # $commands is zsh's command->path hash: a fork-free lookup, vs the subshell
  # that `$(command -v ...)` would spawn 6× per startup.
  local binpath="${commands[$bin]}"
  [[ -n "$binpath" ]] || return 0
  if [[ ! -r "$cache" || "$binpath" -nt "$cache" || "${ZDOTDIR:-$HOME}/.zshrc" -nt "$cache" ]]; then
    "$@" > "$cache" 2>/dev/null
    zcompile -R -- "$cache" 2>/dev/null
  fi
  source "$cache"
}

# --- 1. Homebrew shellenv ---------------------------------------------------
if [[ -x /opt/homebrew/bin/brew ]]; then
  _cache_init brew-shellenv /opt/homebrew/bin/brew shellenv
elif [[ -x /usr/local/bin/brew ]]; then
  _cache_init brew-shellenv /usr/local/bin/brew shellenv
fi
BREW_PREFIX="${HOMEBREW_PREFIX:-/opt/homebrew}"

# --- 2. PATH + tool env -----------------------------------------------------
export PATH="$HOME/bin:$HOME/.local/bin:$HOME/.bun/bin:$PATH"

# mise — replaces nvm/pyenv/rbenv/asdf. Respects .nvmrc, .tool-versions,
# .mise.toml. Activation cost: ~5ms vs nvm's ~600ms.
if command -v mise >/dev/null 2>&1; then
  _cache_init mise-activate mise activate zsh
fi

# Legacy nvm fallback — only loaded if mise isn't installed AND ~/.nvm exists.
# Kept so this dotfiles repo gracefully degrades on a not-fully-bootstrapped box.
if ! command -v mise >/dev/null 2>&1 && [[ -s "$HOME/.nvm/nvm.sh" ]]; then
  export NVM_DIR="$HOME/.nvm"
  for _cmd in nvm node npm npx yarn; do
    eval "${_cmd}() { unset -f nvm node npm npx yarn; \. \"\$NVM_DIR/nvm.sh\"; ${_cmd} \"\$@\"; }"
  done
  unset _cmd
fi

# --- 3. Shared dotfiles -----------------------------------------------------
for file in ~/.{path,exports,aliases,functions,extra}; do
  [ -r "$file" ] && [ -f "$file" ] && source "$file"
done
unset file

# --- 4. compinit (fast cold start) -----------------------------------------
# The slow part of compinit is (a) the fpath security audit (compaudit) and
# (b) rewriting the dump (compdump). We want both at most once per 24h.
#
# The naive `[[ -n $dump(#qN...) ]]` test is BROKEN: when the glob matches
# nothing it expands to zero words, and `[[ -n ]]` with no operand is *true* —
# so the "rebuild" branch fires every single start (~70ms wasted). The robust
# idiom passes the glob result as args to an anonymous function: the dump path
# arrives as $1 only when it matches a regular file modified in the last 24h.
autoload -Uz compinit
_zcompdump="${ZDOTDIR:-$HOME}/.zcompdump"
# Glob qualifier (N.mh-24): N=nullglob, .=regular file, mh-24=modified <24h ago.
# Unquoted so the qualifier actually globs; plain `(...)` form needs no
# extended_glob (the `(#q...)` form does, and erroring there silently broke this).
() {
  if (( $# )); then
    compinit -C -d "$_zcompdump"          # fresh dump (<24h): skip audit, just load
  else
    compinit -d "$_zcompdump"             # stale/missing: full audit + rebuild dump
  fi
} ${_zcompdump}(N.mh-24)
# Compile the dump to bytecode so the next `source` of it is a fast mmap.
# zsh auto-prefers <dump>.zwc when it's newer than <dump>.
if [[ -s "$_zcompdump" && ( ! -s "${_zcompdump}.zwc" || "$_zcompdump" -nt "${_zcompdump}.zwc" ) ]]; then
  zcompile -R -- "${_zcompdump}.zwc" "$_zcompdump" 2>/dev/null
fi
unset _zcompdump

# Case-insensitive + partial-word + substring matching:
#   `Doc<TAB>` -> Documents/, `docu<TAB>` -> Documents/, `mn<TAB>` -> main
zstyle ':completion:*' matcher-list \
  'm:{a-zA-Z}={A-Za-z}' \
  'r:|[._-]=* r:|=*' \
  'l:|=* r:|=*'
zstyle ':completion:*' menu select
zstyle ':completion:*:descriptions' format '[%d]'
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"

# Bun completion (compdef must be defined => after compinit).
[ -s "$HOME/.bun/_bun" ] && source "$HOME/.bun/_bun"

# `g` is the git alias; mirror git's completion onto it.
compdef g=git 2>/dev/null

# ssh hostname completion from ~/.ssh/config.
if [[ -e "$HOME/.ssh/config" ]]; then
  _ssh_hosts=(${${${(@M)${(f)"$(<$HOME/.ssh/config)"}:#Host *}#Host }:#*[*?]*})
  zstyle ':completion:*:(ssh|scp|sftp):*' hosts $_ssh_hosts
  unset _ssh_hosts
fi

# --- 5. plugins (order matters) --------------------------------------------
# fzf-tab BEFORE autosuggestions/highlighter (it wraps the completion widget).
if [[ -r "$BREW_PREFIX/share/fzf-tab/fzf-tab.zsh" ]]; then
  source "$BREW_PREFIX/share/fzf-tab/fzf-tab.zsh"
  # Preview directories and files on tab.
  zstyle ':fzf-tab:complete:cd:*' fzf-preview 'eza -1 --color=always $realpath 2>/dev/null || ls -1 $realpath'
  zstyle ':fzf-tab:complete:(\\|*/|)cat:*' fzf-preview 'bat --color=always $realpath 2>/dev/null || cat $realpath'
  zstyle ':fzf-tab:*' switch-group ',' '.'
  zstyle ':fzf-tab:*' fzf-flags --height=50% --layout=reverse --border --ansi
fi

# fzf keybindings: Ctrl-R (history), Ctrl-T (files), Alt-C (cd).
if [[ -r "$BREW_PREFIX/opt/fzf/shell/key-bindings.zsh" ]]; then
  source "$BREW_PREFIX/opt/fzf/shell/key-bindings.zsh"
fi
if [[ -r "$BREW_PREFIX/opt/fzf/shell/completion.zsh" ]]; then
  source "$BREW_PREFIX/opt/fzf/shell/completion.zsh"
fi
# Use fd / rg under the hood for fzf when available.
if command -v fd >/dev/null 2>&1; then
  export FZF_DEFAULT_COMMAND='fd --type f --hidden --strip-cwd-prefix --exclude .git'
  export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
  export FZF_ALT_C_COMMAND='fd --type d --hidden --strip-cwd-prefix --exclude .git'
fi
export FZF_DEFAULT_OPTS='--height=40% --layout=reverse --border --color=fg:#c0caf5,bg:#1a1b26,hl:#7aa2f7,fg+:#c0caf5,bg+:#292e42,hl+:#7dcfff,info:#7aa2f7,prompt:#7dcfff,pointer:#bb9af7,marker:#9ece6a,spinner:#9ece6a,header:#9ece6a'

# zsh-autosuggestions: gray inline ghost-text from history.
if [[ -r "$BREW_PREFIX/share/zsh-autosuggestions/zsh-autosuggestions.zsh" ]]; then
  source "$BREW_PREFIX/share/zsh-autosuggestions/zsh-autosuggestions.zsh"
  # history only — the `completion` strategy conflicts with fzf-tab (loaded above):
  # its async worker runs fzf-tab's completion hooks, which emit escape sequences
  # that corrupt the screen. Surfaces when typing novel args (e.g. a `cc` prompt)
  # that history can't suggest, so it falls through to completion.
  ZSH_AUTOSUGGEST_STRATEGY=(history)
  ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=#565f89'   # tokyo-night comment color
  ZSH_AUTOSUGGEST_USE_ASYNC=1
fi

# you-should-use: when you type a command that has an alias, it reminds you of
# the alias AFTER the command runs. Teaches you your own shortcuts. Set vars
# before sourcing. (preexec hook, not ZLE — cheap, order-independent.)
if [[ -r "$BREW_PREFIX/share/zsh-you-should-use/you-should-use.plugin.zsh" ]]; then
  export YSU_MESSAGE_POSITION="after"
  export YSU_MODE="BESTMATCH"   # remind about the single best alias, not every match
  export YSU_MESSAGE_FORMAT=$'\e[1;33m💡 alias: use \e[1;36m%alias\e[1;33m for \e[0;33m%command\e[0m'
  source "$BREW_PREFIX/share/zsh-you-should-use/you-should-use.plugin.zsh"
fi

# fast-syntax-highlighting: faster successor to zsh-syntax-highlighting.
# Must be sourced LAST among plugins that hook ZLE.
if [[ -r "$BREW_PREFIX/share/zsh-fast-syntax-highlighting/fast-syntax-highlighting.plugin.zsh" ]]; then
  source "$BREW_PREFIX/share/zsh-fast-syntax-highlighting/fast-syntax-highlighting.plugin.zsh"
fi

# --- 6. starship prompt + direnv + atuin + zoxide --------------------------
# All cached via _cache_init (see section 0) so they don't fork a binary on
# every shell start.
if command -v starship >/dev/null 2>&1; then
  _cache_init starship-init starship init zsh
fi
if command -v direnv >/dev/null 2>&1; then
  _cache_init direnv-hook direnv hook zsh   # auto-load .envrc when cd-ing into a project
fi
# atuin replaces the default Ctrl-R history search with a fuzzy UI backed by
# SQLite. --disable-up-arrow keeps the normal "prefix-match on up-arrow"
# behavior we bind below; atuin only owns Ctrl-R.
if command -v atuin >/dev/null 2>&1; then
  _cache_init atuin-init atuin init zsh --disable-up-arrow
fi
# zoxide is initialized LAST of the hook-based tools so its chpwd hook runs
# after starship/atuin register theirs. _ZO_DOCTOR=0 silences the false-positive
# "init should be at the end" warning — unavoidable when multiple tools add
# precmd/chpwd hooks. `--cmd cd` makes `cd foo` jump to the frecent match.
if command -v zoxide >/dev/null 2>&1; then
  export _ZO_DOCTOR=0
  _cache_init zoxide-init zoxide init zsh --cmd cd
fi

# navi — Ctrl-G opens an interactive, fuzzy cheatsheet and inserts the chosen
# (editable) command at the prompt. Add your own cheats under
# ~/.local/share/navi/cheats/. Cached so it doesn't fork navi each start.
if command -v navi >/dev/null 2>&1; then
  _cache_init navi-widget navi widget zsh
fi

# pay-respects (thefuck successor) goes here if you ever `cargo install` it:
#   command -v pay-respects >/dev/null 2>&1 && _cache_init pay-respects pay-respects zsh --alias oops --nocnf
# Omitted from the default stack — see the note in Brewfile.

# Homebrew command-not-found: when you run a command that isn't installed,
# suggest the brew formula that provides it. Hardcoded path (avoids a
# `$(brew --repository)` fork at startup); the expensive lookup only runs on a
# miss, never on a normal command.
_HB_CNF="/opt/homebrew/Library/Homebrew/command-not-found/handler.sh"
[[ -r "$_HB_CNF" ]] && source "$_HB_CNF"
unset _HB_CNF

# --- 7. AI shell helpers (backed by `llm`) ---------------------------------
# `llm` (Simon Willison's) is the maintained AI pipe (replaces the now-archived
# `mods`). Needs the llm-anthropic plugin + a key:
#   llm install llm-anthropic            (install.sh does this)
#   llm keys set anthropic               (or export ANTHROPIC_API_KEY in ~/.extra)
#
#   ai find files larger than 1G         → suggest a command (prints, doesn't run)
#   explain rsync -aHAX --delete a/ b/   → explain a command
#   <buffer text> + Ctrl-X Ctrl-A        → replace the line with an AI command
#   <anything> | llm 'do X with this'    → arbitrary pipe-to-AI
#   llm chat                             → interactive REPL
# (Named `ai`/`explain`, not `?`/`??`: zsh glob-expands `?` in command position,
#  so a function literally named `?` can't be invoked bare.)
_AI_MODEL="${AI_MODEL:-claude-sonnet-4.6}"   # llm-anthropic alias (dotted)
_ai_cmd_prompt='Reply with ONLY a single shell command for macOS zsh — no markdown, no backticks, no commentary:'
if command -v llm >/dev/null 2>&1; then
  ai() {
    (( $# )) || { print -u2 'usage: ai <natural language description>'; return 2; }
    print -r -- "$*" | llm -m "$_AI_MODEL" -s "$_ai_cmd_prompt" \
      | sed -E 's/^[[:space:]]*```[a-z]*//; s/```[[:space:]]*$//'
  }
  explain() {
    (( $# )) || { print -u2 'usage: explain <command>'; return 2; }
    print -r -- "$*" | llm -m "$_AI_MODEL" \
      -s 'Explain what this shell command does, step by step, in 5 lines or fewer:'
  }
fi

# Ctrl-X Ctrl-A: turn the current line (a description) into a shell command.
_ai_suggest_widget() {
  emulate -L zsh
  local query="${BUFFER}"
  [[ -n "$query" ]] || { zle -M "Type a description, then Ctrl-X Ctrl-A"; return; }
  command -v llm >/dev/null 2>&1 || { zle -M "llm not installed — brew install llm"; return; }
  local suggestion
  suggestion=$(print -r -- "$query" | llm -m "$_AI_MODEL" -s "$_ai_cmd_prompt" 2>/dev/null \
    | sed -E 's/^[[:space:]]*```[a-z]*//; s/```[[:space:]]*$//' | awk 'NF{print; exit}')
  if [[ -n "$suggestion" ]]; then
    BUFFER="$suggestion"; CURSOR=${#BUFFER}
  else
    zle -M "no suggestion (check ANTHROPIC_API_KEY in ~/.extra and \`llm models\`)"
  fi
  zle reset-prompt
}
zle -N _ai_suggest_widget
bindkey '^X^A' _ai_suggest_widget

# --- 7b. Parallel Claude Code agents in git worktrees ----------------------
# Leaner replacement for workmux: lean on Claude Code's native `--worktree`
# (branches off origin/HEAD = main, never merges/pushes — safe with Graphite)
# and tmux + sesh for navigation. One agent per worktree, land via `gt`.
#
#   cc <name>             spawn a Claude agent in a fresh worktree + tmux window
#                          (type your prompt in Claude once it opens)
#   ccls                  list agent worktrees
#   ccrm <name>           remove a finished worktree + its branch (after landing)
#   ccd  /  prefix a      the agent dashboard — jump between running agents
# Repo the worktrees are cut from. Defaults to ask-rogo so `cc <name>` works from
# anywhere (no need to cd in first); override per call or in env:
#   CC_REPO=~/code/other cc <name>
: ${CC_REPO:=$HOME/Documents/ask-rogo}
# Flags every spawned agent runs with. Worktrees are isolated, so agents run
# autonomously (--dangerously-skip-permissions) by default — override per call:
#   CC_FLAGS= cc <name>            (run WITH permission prompts)
: ${CC_FLAGS:=--dangerously-skip-permissions}
cc() {
  emulate -L zsh
  local name="$1"
  [[ -n "$name" ]] || { print -u2 "usage: cc <name>"; return 2; }
  command -v claude >/dev/null 2>&1 || { print -u2 "cc: claude not installed"; return 1; }
  local root; root=$(git -C "$CC_REPO" rev-parse --show-toplevel 2>/dev/null) \
    || { print -u2 "cc: CC_REPO ('$CC_REPO') is not a git repo"; return 1; }
  local repo=${root:t}
  # claude -w creates the worktree off origin/HEAD and starts the session there.
  # We own the tmux part (Ghostty, not iTerm2), so don't use claude's --tmux.
  if [[ -n "$TMUX" ]]; then
    tmux new-window -n "$name" -c "$root" "claude --worktree '$name' ${CC_FLAGS}"
  else
    tmux new-session -A -s "$repo" -n "$name" -c "$root" "claude --worktree '$name' ${CC_FLAGS}"
  fi
}
ccls() {
  local root; root=$(git -C "$CC_REPO" rev-parse --show-toplevel 2>/dev/null) || return 1
  git -C "$root" worktree list
}
ccrm() {
  emulate -L zsh
  local name="$1"
  [[ -n "$name" ]] || { print -u2 "usage: ccrm <name> [--force]"; return 2; }
  shift
  local root; root=$(git -C "$CC_REPO" rev-parse --show-toplevel 2>/dev/null) || return 1
  # Claude names worktrees under .claude/worktrees/<name> on branch worktree-<name>.
  git -C "$root" worktree remove ".claude/worktrees/$name" "$@" \
    && git -C "$root" branch -D "worktree-$name" 2>/dev/null
  git -C "$root" worktree prune
}
# ccland [name] — land a finished agent's worktree as a PR. Run it from inside
# the worktree (after reviewing), or pass the agent name. Submits via Graphite
# (gt) when the repo is gt-initialized, else git push + gh pr create. Never
# touches main; after the PR merges, clean up with `ccrm <name>`.
ccland() {
  emulate -L zsh
  command -v git >/dev/null 2>&1 || return 1
  local common dir branch short n ans
  common="$(git rev-parse --git-common-dir 2>/dev/null)" \
    || { print -u2 "ccland: not in a git repo"; return 1; }
  common="${common:A}"                       # absolute
  if [[ -n "$1" ]]; then
    dir="${common:h}/.claude/worktrees/$1"
    [[ -d "$dir" ]] || { print -u2 "ccland: no worktree '$1' (see: ccls)"; return 1; }
  else
    dir="$(git rev-parse --show-toplevel)"
  fi
  branch="$(git -C "$dir" symbolic-ref --quiet --short HEAD)" \
    || { print -u2 "ccland: detached HEAD in $dir"; return 1; }
  [[ "$branch" == (main|master) ]] && { print -u2 "ccland: refusing to land the trunk ($branch)"; return 1; }
  if [[ -n "$(git -C "$dir" status --porcelain)" ]]; then
    print -u2 "ccland: $dir has uncommitted changes — commit them first."; return 1
  fi
  n="$(git -C "$dir" rev-list --count "main..$branch" 2>/dev/null \
       || git -C "$dir" rev-list --count "origin/HEAD..$branch" 2>/dev/null)"
  [[ -n "$n" && "$n" != 0 ]] || { print -u2 "ccland: nothing to land — '$branch' has no commits beyond main"; return 1; }

  print -P "%B%F{4}── land $branch ($n commit$( ((n>1)) && echo s )) ──%f%b"
  git -C "$dir" --no-pager log --oneline "main..$branch" 2>/dev/null | sed 's/^/  /'
  local how="git push + gh pr create"
  [[ -f "$common/.graphite_repo_config" ]] && command -v gt >/dev/null 2>&1 && how="Graphite (gt submit)"
  print -Pn "%F{3}submit via ${how}? (y/N) %f"; read -r ans
  [[ "$ans" == [yY] ]] || { echo "aborted"; return 1; }

  ( cd "$dir" || exit 1
    if [[ "$how" == Graphite* ]]; then
      gt track --parent main 2>/dev/null || true   # tell Graphite the parent (no-op if tracked)
      gt submit
    else
      git push -u origin "$branch" \
        && { command -v gh >/dev/null 2>&1 && gh pr create --fill --web || print "pushed — open a PR for $branch"; }
    fi
  )
  short="${1:-${branch#worktree-}}"
  print -P "%F{8}after it merges:%f %F{6}ccrm ${short}%f"
}

# Central agent dashboard (also `prefix A` in tmux): all sessions + live preview.
alias ccd='cc-dashboard'

# --- Bracketed paste (safe multi-line paste) -------------------------------
# Guarantees pasted text — multi-line commands, quotes, code — lands as literal
# text you can edit, instead of executing line-by-line. zsh enables this by
# default, but re-assert it AFTER plugins load so nothing clobbers the widget.
# (If a paste ever auto-runs, it's almost always a shell that predates this.)
if [[ -z "${zle_bracketed_paste:-}" ]]; then
  zle_bracketed_paste=($'\e[?2004h' $'\e[?2004l')
fi
bindkey '^[[200~' bracketed-paste 2>/dev/null

# --- History ---------------------------------------------------------------
HISTFILE="$HOME/.zsh_history"
HISTSIZE=100000
SAVEHIST=$HISTSIZE
setopt APPEND_HISTORY INC_APPEND_HISTORY SHARE_HISTORY
setopt HIST_IGNORE_DUPS HIST_IGNORE_ALL_DUPS HIST_IGNORE_SPACE HIST_REDUCE_BLANKS
setopt HIST_FIND_NO_DUPS HIST_SAVE_NO_DUPS
setopt EXTENDED_HISTORY

# --- Misc zsh --------------------------------------------------------------
setopt AUTO_CD             # `foo/` cds into foo
setopt AUTO_PUSHD          # cd pushes onto dir stack
setopt PUSHD_IGNORE_DUPS
setopt PUSHD_SILENT
setopt INTERACTIVE_COMMENTS
setopt NO_BEEP
setopt EXTENDED_GLOB       # `(#q...)`, `^`, `~` globbing — also makes glob qualifiers safe
setopt GLOB_DOTS           # tab-completion includes dotfiles without leading `.`
setopt NO_CASE_GLOB        # case-insensitive globbing
setopt NUMERIC_GLOB_SORT   # foo2 before foo10
setopt HIST_VERIFY         # expand !! / !$ onto the line before running, don't auto-run
# Deliberately NOT setting CORRECT — it intercepts mistyped commands with
# a `[nyae]?` prompt, which feels like completion is broken. `oops` (pay-respects)
# covers the "fix my last command" case far better.

# Useful aliases that depend on the new tools.
command -v eza >/dev/null 2>&1 && {
  alias ls='eza --group-directories-first'
  alias la='eza -la --group-directories-first --icons --git'
  alias lt='eza --tree --level=2 --icons'
}
command -v bat >/dev/null 2>&1 && alias cat='bat --paging=never --plain'

# Keybindings: arrow up/down search history matching current prefix.
autoload -Uz up-line-or-beginning-search down-line-or-beginning-search
zle -N up-line-or-beginning-search
zle -N down-line-or-beginning-search
bindkey '^[[A' up-line-or-beginning-search
bindkey '^[[B' down-line-or-beginning-search
bindkey '^[OA' up-line-or-beginning-search
bindkey '^[OB' down-line-or-beginning-search
# Left/right in BOTH normal (^[[C/D) and application-cursor (^[OC/D) modes. A
# full-screen program (or a paste) that leaves the terminal in DECCKM otherwise
# kills left/right while up/down keep working, since only ^[OA/^[OB were bound.
bindkey '^[[C' forward-char
bindkey '^[[D' backward-char
bindkey '^[OC' forward-char
bindkey '^[OD' backward-char
# Ctrl-arrow: jump by word (Ghostty sends these escape sequences).
bindkey '^[[1;5C' forward-word
bindkey '^[[1;5D' backward-word
# zsh picks vi insert mode here because $EDITOR is nvim, and vi-backward-delete-char
# won't delete past where the current insert/paste began — so backspace stops
# partway through a pasted block. Bind the unrestricted deleters in viins.
bindkey -M viins '^?' backward-delete-char
bindkey -M viins '^H' backward-delete-char
bindkey -M viins '^W' backward-kill-word
bindkey -M viins '^U' backward-kill-line

# --- 8. Cheatsheets & learning ---------------------------------------------
# `cheat` (alias `keys`) — on-demand, colorized cheatsheet of the whole setup.
# The alias section is generated live so it never goes stale. Zero startup cost
# (lazy function). The persistent "press for keys" reminder lives in the tmux
# status bar (see ~/.tmux.conf) and in the tip-of-the-day below.
cheat() {
  print -P "%B%F{4}── fzf / history ──%f%b"
  print -P "  %F{6}Ctrl-R%f atuin history    %F{6}Ctrl-T%f insert file path   %F{6}Alt-C%f cd into subdir"
  print -P "  %F{6}Ctrl-G%f navi cheatsheet  %F{6}Tab%f    fuzzy completion    %F{6}↑/↓%f prefix history"
  print -P "  %F{6}Ctrl-X Ctrl-A%f  turn the typed description into a shell command (AI)"
  print -P "%B%F{4}── helpers ──%f%b"
  print -P "  %F{6}ai <desc>%f  suggest a command       %F{6}explain <cmd>%f explain a command"
  print -P "  %F{6}help <cmd>%f tldr examples (tealdeer) %F{6}cat | llm '…'%f pipe anything to AI"
  print -P "  %F{6}z <dir>%f   zoxide jump               %F{6}lg%f        lazygit"
  print -P "%B%F{4}── agents & learning ──%f%b"
  print -P "  %F{6}cc <name>%f spawn agent in a worktree %F{6}ccd%f / prefix A  agent dashboard"
  print -P "  %F{6}ccland%f    land worktree as a PR (gt) %F{6}ccrm <name>%f remove it after merge"
  print -P "  %F{6}coach%f     what to try next          %F{6}learn%f     interactive tour"
  print -P "%B%F{4}── your aliases ──%f%b  (g = git)"
  alias | sort | sed 's/^/  /' | (bat --style=plain --language=sh --color=always 2>/dev/null || cat)
  print -P "%B%F{4}── tmux ──%f%b  prefix %F{6}Ctrl-a%f, then %F{6}?%f (all keys) or %F{6}Ctrl-h%f (cheatsheet popup)"
  print -P "%F{8}(this menu: cheat | nvim: <space> | ghostty: ghostty-keys)%f"
}
alias keys='cheat'

# `ghostty-keys` — Ghostty has no in-app cheatsheet; grep the live config plus
# the built-in macOS defaults.
ghostty-keys() {
  local cfg="${XDG_CONFIG_HOME:-$HOME/.config}/ghostty/config"
  print -P "%F{6}== your Ghostty keybinds ==%f"
  grep -E '^\s*keybind\s*=' "$cfg" 2>/dev/null | sed -E 's/^\s*keybind\s*=\s*//' \
    | awk -F= '{printf "  %-26s %s\n", $1, substr($0, index($0,"=")+1)}'
  print -P "%F{6}== built-in (macOS) ==%f"
  print "  cmd+t new tab   cmd+w close   cmd+shift+[ ] prev/next tab   cmd+1..9 tab N"
  print "  cmd+enter fullscreen   cmd+grave quick-terminal dropdown"
}

# --- Coach: spot & suggest (learn the setup as you go) ---------------------
# A cheap preexec hook records which power-features you actually use; `coach`
# shows a scorecard of what's left, and the tip-of-the-day preferentially
# nudges a feature you haven't tried yet.
alias coach='cc-coach'
alias learn='cc-learn'

# Map the first word of each command you run to a tracked feature id.
_cc_track() {
  local word="${1%% *}" feat="" used="${XDG_CACHE_HOME:-$HOME/.cache}/cc-coach/used"
  case "$word" in
    cc) feat=cc ;; ccland) feat=ccland ;; ccd|cc-dashboard) feat=ccd ;; ai) feat=ai ;; explain) feat=explain ;;
    llm) feat=llm ;; z) feat=z ;; lg|lazygit) feat=lazygit ;; tldr|help) feat=tldr ;;
    cheat|keys) feat=cheat ;; nvim|vim) feat=nvim ;; gt) feat=gt ;;
    *) return ;;
  esac
  [[ -r "$used" ]] && grep -qxF "$feat" "$used" 2>/dev/null && return
  mkdir -p "${used:h}"; print -r -- "$feat" >> "$used"
}
autoload -Uz add-zsh-hook
add-zsh-hook preexec _cc_track

# Tip-of-the-day: ~60% of the time nudge an unused feature (the coach), else a
# random tip from ~/.config/zsh/tips.txt. Pure-zsh, interactive-gated, ~1-2ms.
_zsh_tip() {
  [[ -o interactive ]] || return
  if (( RANDOM % 5 < 3 )) && command -v cc-coach >/dev/null 2>&1; then
    local nudge; nudge="$(cc-coach --suggest-one 2>/dev/null)"
    if [[ -n "$nudge" ]]; then
      print -Pn "%F{8}coach%f %F{6}"; print -rn -- "$nudge"
      print -P "%f  %F{8}(coach = scorecard · learn = tour)%f"
      return
    fi
  fi
  local f="${XDG_CONFIG_HOME:-$HOME/.config}/zsh/tips.txt"
  [[ -r "$f" ]] || return
  local -a tips; tips=("${(@f)$(<"$f")}")
  (( ${#tips} )) || return
  print -Pn "%F{8}tip%f %F{6}"
  print -rn -- "${tips[$((RANDOM % ${#tips} + 1))]}"
  print -P "%f  %F{8}(type 'cheat' for the cheatsheet · 'learn' for a tour)%f"
}
_zsh_tip
