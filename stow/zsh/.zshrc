# ─── Zinit Bootstrap ─────────────────────────────────────────────────────────
ZINIT_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}/zinit/zinit.git"
if [[ ! -d "$ZINIT_HOME" ]]; then
  mkdir -p "$(dirname $ZINIT_HOME)"
  git clone https://github.com/zdharma-continuum/zinit.git "$ZINIT_HOME"
fi
source "${ZINIT_HOME}/zinit.zsh"

# ─── Plugins (turbo-loaded for speed) ────────────────────────────────────────
zinit light-mode for \
  zdharma-continuum/zinit-annex-bin-gem-node

zinit wait lucid for \
  atinit"ZINIT[COMPINIT_OPTS]=-C; zicompinit; zicdreplay" \
    zdharma-continuum/fast-syntax-highlighting \
  blockf \
    zsh-users/zsh-completions \
  atload"!_zsh_autosuggest_start" \
    zsh-users/zsh-autosuggestions

# ─── History ──────────────────────────────────────────────────────────────────
HISTSIZE=50000
SAVEHIST=50000
HISTFILE=~/.zsh_history
setopt EXTENDED_HISTORY
setopt HIST_EXPIRE_DUPS_FIRST
setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_SPACE
setopt SHARE_HISTORY

# ─── Options ──────────────────────────────────────────────────────────────────
setopt AUTO_CD
setopt AUTO_PUSHD
setopt PUSHD_IGNORE_DUPS
setopt PUSHD_SILENT

# ─── Env ──────────────────────────────────────────────────────────────────────
export EDITOR="nvim"
export VISUAL="nvim"
export PAGER="less"
export MANPAGER="sh -c 'col -bx | bat -l man -p'"

# ─── Path ─────────────────────────────────────────────────────────────────────
typeset -U path
path=(
  $HOME/.local/bin
  $HOME/.cargo/bin
  $path
)

# ─── Tool Init (order matters) ────────────────────────────────────────────────
eval "$(starship init zsh)"
eval "$(zoxide init zsh)"
eval "$(atuin init zsh --disable-up-arrow)"
eval "$(mise activate zsh)"
eval "$(direnv hook zsh)"
eval "$(thefuck --alias)"

# ─── FZF ──────────────────────────────────────────────────────────────────────
source <(fzf --zsh)
export FZF_DEFAULT_OPTS=" \
  --color=bg+:#313244,bg:#1e1e2e,spinner:#f5e0dc,hl:#f38ba8 \
  --color=fg:#cdd6f4,header:#f38ba8,info:#cba6f7,pointer:#f5e0dc \
  --color=marker:#b4befe,fg+:#cdd6f4,prompt:#cba6f7,hl+:#f38ba8 \
  --color=selected-bg:#45475a \
  --multi"
export FZF_DEFAULT_COMMAND="fd --type f --hidden --follow --exclude .git"
export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"

# ─── Aliases ──────────────────────────────────────────────────────────────────
alias ls="eza --icons --group-directories-first"
alias ll="eza -la --icons --group-directories-first --git"
alias lt="eza --tree --level=2 --icons"
alias cat="bat --paging=never"
alias grep="rg"
alias find="fd"
alias du="dust"
alias ps="procs"
alias top="btop"
alias diff="delta"
alias lg="lazygit"
alias ld="lazydocker"
alias v="nvim"
alias vi="nvim"
alias vim="nvim"
alias y="yazi"

# ─── Tip of the Day ──────────────────────────────────────────────────────────
if [[ -o interactive ]] && command -v dotfiles-tips &>/dev/null; then
  dotfiles-tips
fi

# ─── Extensibility Hook ──────────────────────────────────────────────────────
for f in ~/.local/dotfiles.d/*.zsh(N); do
  source "$f"
done
