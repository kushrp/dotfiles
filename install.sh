#!/usr/bin/env bash
# One-shot installer for kushrp/dotfiles.
#
# Usage (after `git clone`):
#   ./install.sh                  # full install, prompts before .macos defaults
#   ./install.sh --no-brew        # skip Homebrew + brew bundle
#   ./install.sh --with-macos -y  # also apply .macos defaults non-interactively
#
# Design rules:
#   1. Idempotent — every step is safe to re-run.
#   2. Never silently overwrite — existing files are moved to
#      ~/.dotfiles-backup/<timestamp>/ before being replaced by a symlink.
#   3. Never abort early — failures are collected and printed at the end so
#      a single broken step doesn't hide downstream problems.
#   4. OS-aware — macOS is fully supported today; Linux support is stubbed
#      step-by-step (each platform-specific function branches on $OS).

set -uo pipefail   # intentionally not -e; we collect failures rather than abort.

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_ROOT="$HOME/.dotfiles-backup"
BACKUP_DIR="$BACKUP_ROOT/$(date +%Y%m%d-%H%M%S)"

SKIP_BREW=0
SKIP_CASKS=0
SKIP_MACOS=1            # destructive, opt-in via --with-macos
ASSUME_YES=0
for arg in "$@"; do
  case "$arg" in
    --no-brew)     SKIP_BREW=1 ;;
    --no-casks)    SKIP_CASKS=1 ;;
    --no-macos)    SKIP_MACOS=1 ;;
    --with-macos)  SKIP_MACOS=0 ;;
    -y|--yes)      ASSUME_YES=1 ;;
    -h|--help)
      sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) printf 'Unknown arg: %s\n' "$arg" >&2; exit 2 ;;
  esac
done

# --- logging ---------------------------------------------------------------
log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
ok()   { printf '  \033[1;32m✓\033[0m %s\n' "$*"; }
warn() { printf '  \033[1;33m!\033[0m %s\n' "$*" >&2; }
err()  { printf '  \033[1;31m✗\033[0m %s\n' "$*" >&2; }

FAILURES=()
fail() { FAILURES+=("$1"); err "$1"; }

ensure_backup_dir() {
  [[ -d "$BACKUP_DIR" ]] || { mkdir -p "$BACKUP_DIR"; log "Backups → $BACKUP_DIR"; }
}

# --- OS detection ----------------------------------------------------------
# Sets:
#   OS        macos | linux
#   DISTRO    "" on macos; on linux: the ID from /etc/os-release (ubuntu, debian, fedora, arch, ...)
#   PKG_MGR   brew | apt | dnf | pacman | ""
detect_os() {
  case "$(uname -s)" in
    Darwin)
      OS="macos"
      DISTRO=""
      PKG_MGR="brew"
      ;;
    Linux)
      OS="linux"
      DISTRO=""
      if [[ -f /etc/os-release ]]; then
        # shellcheck disable=SC1091
        DISTRO="$(. /etc/os-release && echo "${ID:-}")"
      fi
      if   command -v apt-get >/dev/null; then PKG_MGR="apt"
      elif command -v dnf     >/dev/null; then PKG_MGR="dnf"
      elif command -v pacman  >/dev/null; then PKG_MGR="pacman"
      else PKG_MGR=""
      fi
      ;;
    *) err "Unsupported OS: $(uname -s)"; exit 1 ;;
  esac
}

# --- preflight -------------------------------------------------------------
preflight() {
  log "Preflight"
  ok "$OS${DISTRO:+ ($DISTRO)} — pkg manager: ${PKG_MGR:-none}"

  case "$OS" in
    macos)
      ok "macOS $(sw_vers -productVersion) on $(uname -m)"
      if ! xcode-select -p &>/dev/null; then
        log "Installing Xcode Command Line Tools (a GUI prompt will appear)..."
        xcode-select --install || true
        warn "Wait for the installer to finish, then re-run ./install.sh"
        exit 1
      fi
      ok "Xcode Command Line Tools present"
      ;;
    linux)
      command -v git  >/dev/null || warn "git missing — install via $PKG_MGR first"
      command -v curl >/dev/null || warn "curl missing — install via $PKG_MGR first"
      ;;
  esac
}

# --- package manager bootstrap --------------------------------------------
install_package_manager() {
  (( SKIP_BREW )) && { warn "skipping package-manager bootstrap (--no-brew)"; return; }
  case "$OS" in
    macos)
      log "Homebrew"
      if command -v brew &>/dev/null; then
        ok "already installed: $(brew --version | head -n1)"
      else
        log "installing Homebrew (non-interactive)..."
        NONINTERACTIVE=1 /bin/bash -c \
          "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" \
          || { fail "Homebrew install"; return; }
      fi
      # Make brew visible in *this* script run.
      if [[ -x /opt/homebrew/bin/brew ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
      elif [[ -x /usr/local/bin/brew ]]; then
        eval "$(/usr/local/bin/brew shellenv)"
      fi
      ;;
    linux)
      log "Package manager"
      if [[ -z "$PKG_MGR" ]]; then
        fail "no supported package manager found (apt/dnf/pacman)"
      else
        ok "using $PKG_MGR"
      fi
      ;;
  esac
}

install_packages() {
  (( SKIP_BREW )) && return
  case "$OS" in
    macos)
      command -v brew &>/dev/null || { fail "brew not on PATH, skipping bundle"; return; }

      # Cache sudo upfront so cask installs that need to chmod or run pkg
      # installers don't fail half-way through with "a terminal is required
      # to read the password". Skipped silently in fully non-interactive runs.
      if (( ! SKIP_CASKS )) && [[ -t 0 ]] && ! sudo -n true 2>/dev/null; then
        log "brew bundle may need sudo for some casks — caching credentials"
        sudo -v || warn "sudo cache failed; some casks may need manual install"
      fi

      local bundle_args=()
      if (( SKIP_CASKS )); then
        # Filter out cask lines on the fly so we only install formulae.
        log "brew bundle (formulae only, --no-casks)"
        grep -v '^[[:space:]]*cask ' "$DOTFILES/Brewfile" \
          | brew bundle --file=- \
          || fail "brew bundle formulae (see output above)"
      else
        log "brew bundle (Brewfile)"
        brew bundle --file="$DOTFILES/Brewfile" \
          || fail "brew bundle (some entries failed; see output above)"
      fi
      if [[ -f "$DOTFILES/Brewfile.local" ]]; then
        log "brew bundle (Brewfile.local)"
        brew bundle --file="$DOTFILES/Brewfile.local" \
          || fail "brew bundle Brewfile.local"
      fi
      ;;
    linux)
      local list="$DOTFILES/linux/packages.$PKG_MGR.txt"
      if [[ ! -f "$list" ]]; then
        warn "no package list for $PKG_MGR at $list — skipping"
        return
      fi
      log "Installing packages via $PKG_MGR ($list)"
      case "$PKG_MGR" in
        apt)    sudo apt-get update && xargs -a "$list" sudo apt-get install -y ;;
        dnf)    xargs -a "$list" sudo dnf install -y ;;
        pacman) xargs -a "$list" sudo pacman -S --noconfirm --needed ;;
      esac || fail "$PKG_MGR install"
      ;;
  esac
}

# --- Bun (cross-platform, installs via bun.sh) -----------------------------
install_bun() {
  log "Bun"
  if command -v bun &>/dev/null || [[ -x "$HOME/.bun/bin/bun" ]]; then
    ok "already installed"
    return
  fi
  curl -fsSL https://bun.sh/install | bash || fail "Bun install"
}

# --- symlinks (OS-independent) ---------------------------------------------
DOTFILES_TO_LINK=(
  .aliases
  .bash_profile
  .bash_prompt
  .bashrc
  .curlrc
  .editorconfig
  .exports
  .functions
  .gitattributes
  .gitconfig
  .gvimrc
  .hgignore
  .hushlogin
  .inputrc
  .screenrc
  .tmux.conf
  .vimrc
  .wgetrc
  .zprofile
  .zshrc
)

link_file() {
  local src="$1" dst="$2"
  if [[ ! -e "$src" ]]; then warn "missing in repo: $src"; return; fi
  if [[ -L "$dst" && "$(readlink "$dst")" == "$src" ]]; then return; fi
  if [[ -e "$dst" || -L "$dst" ]]; then
    ensure_backup_dir
    mv "$dst" "$BACKUP_DIR/" || { fail "backup $dst"; return; }
  fi
  mkdir -p "$(dirname "$dst")"
  ln -s "$src" "$dst" || fail "symlink $dst"
}

symlink_dotfiles() {
  log "Linking dotfiles into \$HOME"
  for name in "${DOTFILES_TO_LINK[@]}"; do
    link_file "$DOTFILES/$name" "$HOME/$name"
  done
  ok "shell + tool dotfiles linked"
}

setup_ghostty() {
  log "Ghostty config"
  link_file "$DOTFILES/.config/ghostty/config" "$HOME/.config/ghostty/config"
  ok "linked → ~/.config/ghostty/config"
}

ensure_vim_dirs() {
  mkdir -p "$HOME/.vim/backups" "$HOME/.vim/swaps" "$HOME/.vim/undo"
}

setup_extra() {
  log "~/.extra (secrets, identity)"
  if [[ -f "$HOME/.extra" ]]; then
    ok "already exists, leaving alone"
    return
  fi
  cp "$DOTFILES/.extra.example" "$HOME/.extra" || { fail "seed ~/.extra"; return; }
  chmod 600 "$HOME/.extra"
  warn "created from template — edit it to set git identity + tokens:"
  warn "    \$EDITOR ~/.extra"
}

set_default_shell() {
  log "Default shell"
  if [[ "${SHELL:-}" == *zsh* ]]; then
    ok "already zsh ($SHELL)"
    return
  fi
  local target
  case "$OS" in
    macos) target="/bin/zsh" ;;
    linux) target="$(command -v zsh || true)" ;;
  esac
  if [[ -z "$target" || ! -x "$target" ]]; then
    warn "zsh not found, skipping chsh"
    return
  fi
  if ! grep -q "^${target}$" /etc/shells 2>/dev/null; then
    warn "$target not listed in /etc/shells; skipping chsh"
    return
  fi
  chsh -s "$target" || fail "chsh -s $target"
}

# --- OS-specific defaults --------------------------------------------------
apply_os_defaults() {
  (( SKIP_MACOS )) && { warn "skipping OS defaults — pass --with-macos to apply on macOS"; return; }
  case "$OS" in
    macos)
      log ".macos (system defaults)"
      if (( ! ASSUME_YES )); then
        read -rp "  Apply .macos system defaults? Some require a reboot. (y/N) " reply
        [[ "$reply" =~ ^[Yy]$ ]] || { warn "skipped"; return; }
      fi
      bash "$DOTFILES/.macos" || fail ".macos"
      ;;
    linux)
      warn "no OS defaults script for Linux yet"
      ;;
  esac
}

# --- summary ---------------------------------------------------------------
summary() {
  echo
  if (( ${#FAILURES[@]} == 0 )); then
    printf '\033[1;32m==> All steps succeeded.\033[0m\n'
  else
    printf '\033[1;31m==> Completed with %d failure(s):\033[0m\n' "${#FAILURES[@]}"
    for f in "${FAILURES[@]}"; do printf '    - %s\n' "$f"; done
  fi
  [[ -d "$BACKUP_DIR" ]] && printf '    backups: %s\n' "$BACKUP_DIR"

  cat <<'EOF'

Next:
  1. Open a new terminal (or `exec zsh -l`) so the new shell config loads.
  2. Edit ~/.extra to set git identity + API tokens (it is gitignored).
  3. Sign into gh:  gh auth login
  4. (macOS) Launch Ghostty — it will pick up ~/.config/ghostty/config.
  5. (Optional) Re-run with --with-macos to apply ~/.macos defaults.
EOF
}

main() {
  detect_os
  preflight
  install_package_manager
  install_packages
  install_bun
  ensure_vim_dirs
  symlink_dotfiles
  setup_ghostty
  setup_extra
  set_default_shell
  apply_os_defaults
  summary
}

main "$@"
