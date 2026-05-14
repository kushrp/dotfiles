#!/usr/bin/env bash
set -euo pipefail

# ─── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${PURPLE}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# ─── Detect Environment ──────────────────────────────────────────────────────
OS="unknown"
HEADLESS=false
DRY_RUN=false

case "$(uname -s)" in
  Darwin) OS="macos" ;;
  Linux)  OS="linux" ;;
  *)      error "Unsupported OS: $(uname -s)" ;;
esac

for arg in "$@"; do
  case "$arg" in
    --headless) HEADLESS=true ;;
    --dry-run)  DRY_RUN=true ;;
  esac
done

if [[ "$OS" == "linux" ]] && [[ -z "${DISPLAY:-}" ]] && [[ -z "${WAYLAND_DISPLAY:-}" ]]; then
  HEADLESS=true
fi

DOTFILES_DIR="$HOME/.dotfiles"
BACKUP_DIR="$HOME/.dotfiles-backup/$(date +%Y%m%d-%H%M%S)"

info "OS: $OS | Headless: $HEADLESS | Dry run: $DRY_RUN"
info "Dotfiles: $DOTFILES_DIR"

# ─── Clone or Update Repo ────────────────────────────────────────────────────
if [[ -d "$DOTFILES_DIR" ]]; then
  info "Updating existing dotfiles..."
  git -C "$DOTFILES_DIR" pull --rebase --quiet
else
  info "Cloning dotfiles..."
  git clone https://github.com/kushrp/dotfiles.git "$DOTFILES_DIR"
fi

cd "$DOTFILES_DIR"

# ─── Package Manager ─────────────────────────────────────────────────────────
install_homebrew() {
  if ! command -v brew &>/dev/null; then
    info "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    eval "$(/opt/homebrew/bin/brew shellenv)"
  fi
  success "Homebrew ready"
}

install_apt_packages() {
  info "Installing apt packages..."
  sudo apt-get update -qq
  xargs -a packages.txt sudo apt-get install -y -qq
  success "apt packages installed"
}

install_linux_binaries() {
  info "Installing binaries not in apt..."
  local bin_dir="$HOME/.local/bin"
  mkdir -p "$bin_dir"

  # Starship
  if ! command -v starship &>/dev/null; then
    curl -sS https://starship.rs/install.sh | sh -s -- -y
  fi

  # Atuin
  if ! command -v atuin &>/dev/null; then
    curl -sSL https://raw.githubusercontent.com/atuinsh/atuin/main/install.sh | bash -s -- --no-modify-path
  fi

  # mise
  if ! command -v mise &>/dev/null; then
    curl https://mise.jdx.dev/install.sh | sh
  fi

  # yazi
  if ! command -v yazi &>/dev/null; then
    cargo install --locked yazi-fm yazi-cli 2>/dev/null || warn "yazi requires cargo — skipping"
  fi

  # lazygit
  if ! command -v lazygit &>/dev/null; then
    LAZYGIT_VERSION=$(curl -s "https://api.github.com/repos/jesseduffield/lazygit/releases/latest" | grep -Po '"tag_name": "v\K[^"]*')
    curl -Lo /tmp/lazygit.tar.gz "https://github.com/jesseduffield/lazygit/releases/latest/download/lazygit_${LAZYGIT_VERSION}_Linux_x86_64.tar.gz"
    tar xf /tmp/lazygit.tar.gz -C "$bin_dir" lazygit
    rm /tmp/lazygit.tar.gz
  fi

  # delta
  if ! command -v delta &>/dev/null; then
    cargo install git-delta 2>/dev/null || warn "delta requires cargo — skipping"
  fi

  # bat (alias batcat on debian)
  if command -v batcat &>/dev/null && ! command -v bat &>/dev/null; then
    ln -sf "$(which batcat)" "$bin_dir/bat"
  fi

  # fd (alias fdfind on debian)
  if command -v fdfind &>/dev/null && ! command -v fd &>/dev/null; then
    ln -sf "$(which fdfind)" "$bin_dir/fd"
  fi

  # eza
  if ! command -v eza &>/dev/null; then
    cargo install eza 2>/dev/null || warn "eza requires cargo — skipping"
  fi

  # zoxide
  if ! command -v zoxide &>/dev/null; then
    curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh
  fi

  # just
  if ! command -v just &>/dev/null; then
    curl --proto '=https' --tlsv1.2 -sSf https://just.systems/install.sh | bash -s -- --to "$bin_dir"
  fi

  # thefuck
  if ! command -v thefuck &>/dev/null; then
    pip3 install --user thefuck 2>/dev/null || warn "thefuck requires pip — skipping"
  fi

  # btop
  if ! command -v btop &>/dev/null; then
    sudo snap install btop 2>/dev/null || warn "btop: install manually"
  fi

  success "Linux binaries installed"
}

# ─── Backup Conflicts ────────────────────────────────────────────────────────
backup_conflicts() {
  info "Checking for conflicts..."
  local had_conflicts=false

  for pkg_dir in stow/*/; do
    local pkg
    pkg=$(basename "$pkg_dir")
    # Dry-run stow to detect conflicts
    if ! stow -d stow -t "$HOME" --no "$pkg" 2>/dev/null; then
      had_conflicts=true
      info "Backing up conflicts for: $pkg"
      mkdir -p "$BACKUP_DIR"

      # Portable conflict extraction: handles both old ("existing target is not owned by stow: PATH")
      # and new ("over existing target PATH since ...") stow output formats. Uses sed (BSD/GNU compat).
      stow -d stow -t "$HOME" --no "$pkg" 2>&1 \
        | sed -nE -e 's/.*existing target is not owned by stow: (.*)$/\1/p' \
                  -e 's/.*over existing target (.+) since.*/\1/p' \
        | while read -r file; do
        local src="$HOME/$file"
        if [[ -e "$src" ]] && [[ ! -L "$src" ]]; then
          mkdir -p "$BACKUP_DIR/$(dirname "$file")"
          mv "$src" "$BACKUP_DIR/$file"
          info "  Backed up: $file"
        fi
      done
    fi
  done

  if [[ "$had_conflicts" == true ]]; then
    success "Conflicts backed up to: $BACKUP_DIR"
  fi
}

# ─── Stow All Packages ───────────────────────────────────────────────────────
stow_packages() {
  info "Stowing configs..."

  local packages=(zsh starship tmux nvim git atuin bat btop mise nb lazygit yazi)

  if [[ "$HEADLESS" == false ]]; then
    packages+=(ghostty)
  fi

  for pkg in "${packages[@]}"; do
    if [[ -d "stow/$pkg" ]]; then
      stow -d stow -t "$HOME" --restow "$pkg"
      success "  Stowed: $pkg"
    fi
  done
}

# ─── Post-Install Setup ──────────────────────────────────────────────────────
setup_fonts() {
  if [[ "$HEADLESS" == true ]]; then
    return
  fi

  if [[ "$OS" == "linux" ]]; then
    local font_dir="$HOME/.local/share/fonts"
    if [[ ! -f "$font_dir/JetBrainsMonoNerdFont-Regular.ttf" ]]; then
      info "Installing JetBrains Mono Nerd Font..."
      mkdir -p "$font_dir"
      curl -fLo /tmp/JetBrainsMono.zip "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip"
      unzip -q /tmp/JetBrainsMono.zip -d "$font_dir"
      rm /tmp/JetBrainsMono.zip
      fc-cache -f
      success "Nerd Font installed"
    fi
  fi
}

setup_tmux() {
  if [[ ! -d "$HOME/.tmux/plugins/tpm" ]]; then
    info "Installing TPM..."
    git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
    success "TPM installed"
  fi
}

setup_nvim() {
  info "Bootstrapping Neovim plugins..."
  nvim --headless "+Lazy! sync" +qa 2>/dev/null
  success "Neovim plugins synced"
}

setup_bat_themes() {
  if command -v bat &>/dev/null; then
    local theme_dir
    theme_dir="$(bat --config-dir)/themes"
    if [[ ! -d "$theme_dir/catppuccin" ]]; then
      mkdir -p "$theme_dir"
      curl -fLo "$theme_dir/Catppuccin Mocha.tmTheme" \
        "https://raw.githubusercontent.com/catppuccin/bat/main/themes/Catppuccin%20Mocha.tmTheme"
      bat cache --build
    fi
  fi
}

setup_mise_runtimes() {
  if command -v mise &>/dev/null; then
    info "Installing mise runtimes (python, node)..."
    mise install --yes 2>/dev/null || true
    success "mise runtimes ready"
  fi
}

setup_extensibility_dir() {
  mkdir -p "$HOME/.local/dotfiles.d"
  if [[ ! -f "$HOME/.local/dotfiles.d/secrets.zsh" ]]; then
    cat > "$HOME/.local/dotfiles.d/secrets.zsh" << 'EOF'
# Add API keys here (this file is not tracked by git)
# export ANTHROPIC_API_KEY="sk-ant-..."
# export OPENAI_API_KEY="sk-..."
EOF
  fi
  success "Extensibility dir ready: ~/.local/dotfiles.d/"
}

setup_scripts() {
  local bin_dir="$HOME/.local/bin"
  mkdir -p "$bin_dir"
  for script in scripts/*; do
    if [[ -f "$script" ]]; then
      chmod +x "$script"
      ln -sf "$DOTFILES_DIR/$script" "$bin_dir/$(basename "$script")"
    fi
  done
  success "Scripts linked to ~/.local/bin/"
}

# ─── Main ─────────────────────────────────────────────────────────────────────
main() {
  echo ""
  echo -e "${PURPLE}╔══════════════════════════════════════════╗${NC}"
  echo -e "${PURPLE}║     Portable Dotfiles Installer          ║${NC}"
  echo -e "${PURPLE}╚══════════════════════════════════════════╝${NC}"
  echo ""

  if [[ "$DRY_RUN" == true ]]; then
    info "── DRY RUN: showing what would happen ──"
    echo ""

    # Report packages
    if [[ "$OS" == "macos" ]]; then
      info "Would install Homebrew packages from Brewfile:"
      grep '^brew\|^cask' Brewfile | sed 's/^/    /'
    else
      info "Would install apt packages from packages.txt:"
      grep -v '^#' packages.txt | grep -v '^$' | sed 's/^/    /'
    fi
    echo ""

    # Report stow conflicts
    info "Checking for stow conflicts..."
    local packages=(zsh starship tmux nvim git atuin bat btop mise nb lazygit yazi)
    if [[ "$HEADLESS" == false ]]; then
      packages+=(ghostty)
    fi

    local conflict_found=false
    for pkg in "${packages[@]}"; do
      if [[ -d "stow/$pkg" ]]; then
        local conflicts
        conflicts=$(stow -d stow -t "$HOME" --no "$pkg" 2>&1 | grep "existing target" || true)
        if [[ -n "$conflicts" ]]; then
          conflict_found=true
          warn "Conflicts for $pkg (would backup to $BACKUP_DIR):"
          echo "$conflicts" | sed 's/^/    /'
        fi
      fi
    done
    if [[ "$conflict_found" == false ]]; then
      success "No stow conflicts detected"
    fi
    echo ""

    # Report what would be stowed
    info "Would stow these packages → ~/"
    for pkg in "${packages[@]}"; do
      if [[ -d "stow/$pkg" ]]; then
        echo "    $pkg"
      fi
    done
    echo ""

    # Report post-install
    info "Post-install steps that would run:"
    echo "    - Install Nerd Font (if headful + Linux)"
    echo "    - Install TPM (tmux plugin manager)"
    echo "    - Bootstrap Neovim plugins (Lazy sync)"
    echo "    - Download Catppuccin bat theme"
    echo "    - Install mise runtimes (python 3.12, node 22)"
    echo "    - Create ~/.local/dotfiles.d/ extensibility dir"
    echo "    - Symlink scripts to ~/.local/bin/"
    echo ""

    success "Dry run complete. Run without --dry-run to install."
    return
  fi

  # 1. Package manager + packages
  if [[ "$OS" == "macos" ]]; then
    install_homebrew
    info "Installing packages from Brewfile..."
    if [[ "$HEADLESS" == true ]]; then
      brew bundle --file=Brewfile 2>/dev/null | grep -v "^Skipping"
    else
      brew bundle --file=Brewfile
    fi
    success "Brew packages installed"
  else
    install_apt_packages
    install_linux_binaries
  fi

  # 2. Backup + Stow
  backup_conflicts
  stow_packages

  # 3. Post-install
  setup_fonts
  setup_tmux
  setup_nvim
  setup_bat_themes
  setup_mise_runtimes
  setup_extensibility_dir
  setup_scripts

  # 4. Change shell to zsh if needed
  if [[ "$SHELL" != *"zsh"* ]]; then
    info "Changing default shell to zsh..."
    chsh -s "$(which zsh)" || warn "Could not change shell — run: chsh -s \$(which zsh)"
  fi

  # 5. Done
  echo ""
  echo -e "${GREEN}╔══════════════════════════════════════════╗${NC}"
  echo -e "${GREEN}║          Installation Complete!          ║${NC}"
  echo -e "${GREEN}╚══════════════════════════════════════════╝${NC}"
  echo ""
  echo -e "  ${BLUE}Getting Started:${NC}"
  echo ""
  echo "  1. Open a new terminal (or run: exec zsh)"
  echo "  2. Run: tmux"
  echo "  3. Run: nvim"
  echo "  4. Run: dotfiles-tips"
  echo "  5. Run: dotfiles-learn"
  echo ""
  echo -e "  ${PURPLE}Config:${NC} ~/.local/dotfiles.d/*.zsh"
  echo -e "  ${PURPLE}Update:${NC} dotfiles-update"
  echo -e "  ${PURPLE}Learn:${NC}  dotfiles-learn"
  echo ""
}

main "$@"
