# Brewfile — declarative install list for `brew bundle`.
# `install.sh` runs `brew bundle --file=Brewfile`. Safe to re-run; brew
# bundle skips anything already installed.
#
# Personal additions go in `Brewfile.local` (gitignored), which install.sh
# also runs if it exists.

# --- Taps --------------------------------------------------------------------
# (no custom taps required today)

# --- Shells & shell tooling --------------------------------------------------
brew "bash"                # newer bash than macOS's 3.x — required by some scripts
brew "bash-completion@2"
brew "zsh-completions"

# --- GNU userland (mac's BSD versions are dated) -----------------------------
brew "coreutils"
brew "findutils"
brew "gnu-sed"
brew "grep"
brew "moreutils"           # sponge, ts, vidir, etc.

# --- Core CLI ---------------------------------------------------------------
brew "git"
brew "git-lfs"
brew "gh"                  # GitHub CLI — also the canonical token store (see .extra)
brew "graphite"            # gt CLI used by ask-rogo
brew "openssh"
brew "curl"
brew "wget"
brew "jq"
brew "yq"
brew "ripgrep"
brew "fd"
brew "fzf"
brew "bat"
brew "eza"
brew "tree"
brew "tmux"
brew "vim"
brew "htop"
brew "watch"
brew "mas"                 # mac App Store CLI

# --- Runtimes (for the ask-rogo monorepo and general dev) --------------------
brew "node"
brew "nvm"
brew "go"
brew "python@3.13"
brew "postgresql@16"
brew "redis"

# --- Container/VM tooling ---------------------------------------------------
brew "colima"
brew "docker"
brew "docker-compose"
brew "docker-completion"
brew "lima"

# --- Secrets / crypto --------------------------------------------------------
brew "gnupg"
brew "mkcert"

# --- GUI apps (casks) --------------------------------------------------------
cask "ghostty"             # the terminal this repo configures
cask "1password"
cask "1password-cli"
cask "raycast"
cask "maccy"               # clipboard history
cask "google-chrome"
cask "cursor"
cask "visual-studio-code"
cask "slack"
cask "linear"
cask "notion"
cask "gcloud-cli"
cask "tailscale"
cask "claude"              # Claude desktop app

# --- Fonts (needed by Ghostty config) ----------------------------------------
cask "font-jetbrains-mono"
cask "font-jetbrains-mono-nerd-font"
