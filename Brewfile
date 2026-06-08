# Brewfile — declarative install list for `brew bundle`.
# `install.sh` runs `brew bundle --file=Brewfile`. Safe to re-run; brew
# bundle skips anything already installed.
#
# Personal additions go in `Brewfile.local` (gitignored), which install.sh
# also runs if it exists.

# --- Taps --------------------------------------------------------------------
tap "withgraphite/tap"     # the `gt` Graphite CLI (not in homebrew-core)

# --- Shells & shell tooling --------------------------------------------------
brew "bash"                # newer bash than macOS's 3.x — required by some scripts
brew "bash-completion@2"
brew "zsh-completions"
brew "zsh-autosuggestions"           # fish-style ghost-text from history
brew "zsh-fast-syntax-highlighting"  # colorize commands as you type
brew "zsh-you-should-use"            # nags when an alias exists — teaches your own shortcuts
brew "fzf-tab"                       # fuzzy tab completion menu
brew "starship"                      # cross-shell prompt (Rust, fast)
brew "zoxide"                        # `cd foo` jumps to most-frecent match
brew "atuin"                         # magical shell history (SQLite + fuzzy UI on Ctrl-R)
brew "direnv"                        # auto-load .envrc when cd-ing into a project
brew "mise"                          # replaces nvm/pyenv/rbenv/asdf; per-project tool versions
brew "lazygit"                       # full-screen git TUI
brew "git-delta"                     # syntax-highlighted git diffs
brew "sesh"                          # smart tmux session manager (run `sesh connect`; no key bound — agents live as panes, use `prefix a`)
brew "terminal-notifier"             # macOS notifications (Claude Code finish hook)

# --- Learning / discoverability ----------------------------------------------
brew "navi"                # Ctrl-G interactive cheatsheet → inserts an editable command
brew "tealdeer"            # `tldr` — simplified man pages with real examples (Rust; NOT the EOL node `tldr`)
brew "llm"                 # AI pipe: `cat err.log | llm 'what's wrong'` (replaces archived `mods`)
# pay-respects (thefuck successor) intentionally omitted: only ships as a
# checksum-drifting nightly tap that breaks `brew bundle`. Want it? `cargo
# install pay-respects` and add the eval to ~/.extra. The AI `?` helper +
# atuin history cover "fix my last command" robustly in the meantime.

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
brew "withgraphite/tap/graphite"   # gt CLI (must be tap-qualified; bare "graphite" is a different/unknown formula)
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
brew "neovim"
brew "htop"
brew "watch"
brew "mas"                 # mac App Store CLI
brew "pre-commit"          # runs hooks from .pre-commit-config.yaml
brew "gitleaks"            # secret scanner used by the pre-commit pipeline

# --- Runtimes (for the ask-rogo monorepo and general dev) --------------------
# Note: `mise` is the version manager (see above). It auto-installs Node /
# Python / Go / Ruby etc. via `.tool-versions` or `.mise.toml`. Brew-installed
# runtimes below are global fallbacks for tools that probe $PATH directly.
brew "node"
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
