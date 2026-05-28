#!/usr/bin/env zsh
# zsh equivalent of .bash_profile. Sources the shared dotfiles so the
# same .aliases / .functions / .exports / .extra work in both shells.

# --- Homebrew shellenv (Apple Silicon first, then Intel fallback) -----------
if [[ -x /opt/homebrew/bin/brew ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
elif [[ -x /usr/local/bin/brew ]]; then
  eval "$(/usr/local/bin/brew shellenv)"
fi

# --- PATH --------------------------------------------------------------------
# ~/bin is the upstream convention; ~/.local/bin is standard XDG-ish; ~/.bun/bin for Bun.
export PATH="$HOME/bin:$HOME/.local/bin:$HOME/.bun/bin:$PATH"

# --- nvm ---------------------------------------------------------------------
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

# --- Bun completions ---------------------------------------------------------
[ -s "$HOME/.bun/_bun" ] && source "$HOME/.bun/_bun"

# --- Shared dotfiles ---------------------------------------------------------
# Files are optional. .extra is gitignored and holds tokens / identity.
#   ~/.path      - extend $PATH
#   ~/.exports   - env vars (the dotfile is bash-flavored but valid zsh)
#   ~/.aliases   - shell aliases
#   ~/.functions - shell functions
#   ~/.extra     - secrets, machine-local overrides (never committed)
for file in ~/.{path,exports,aliases,functions,extra}; do
  [ -r "$file" ] && [ -f "$file" ] && source "$file"
done
unset file

# --- zsh completion ----------------------------------------------------------
autoload -Uz compinit
# Cache: regenerate at most once a day, otherwise just read the dump.
if [[ -n ${ZDOTDIR:-$HOME}/.zcompdump(#qN.mh+24) ]]; then
  compinit
else
  compinit -C
fi
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'

# Treat `g` as a git alias for completion too (matches .aliases).
compdef g=git 2>/dev/null

# --- History -----------------------------------------------------------------
HISTFILE="$HOME/.zsh_history"
HISTSIZE=32768
SAVEHIST=$HISTSIZE
setopt APPEND_HISTORY INC_APPEND_HISTORY SHARE_HISTORY
setopt HIST_IGNORE_DUPS HIST_IGNORE_SPACE HIST_REDUCE_BLANKS

# --- Misc zsh ----------------------------------------------------------------
setopt AUTO_CD            # `foo/` cds into foo
setopt CORRECT            # autocorrect mistyped commands

# --- ssh hostname completion (matches upstream .bash_profile behavior) -------
if [[ -e "$HOME/.ssh/config" ]]; then
  hosts=(${${${(@M)${(f)"$(<$HOME/.ssh/config)"}:#Host *}#Host }:#*[*?]*})
  zstyle ':completion:*:(ssh|scp|sftp):*' hosts $hosts
  unset hosts
fi
