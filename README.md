<h1 align="center">
  <img src="https://raw.githubusercontent.com/catppuccin/catppuccin/main/assets/logos/exports/1544x1544_circle.png" width="100" alt=""/>
  <br>
  dotfiles
</h1>

<p align="center">
  <em>One command. Any machine. Beautiful terminal.</em>
</p>

<p align="center">
  <a href="https://github.com/kushrp/dotfiles/actions/workflows/ci.yml">
    <img src="https://github.com/kushrp/dotfiles/actions/workflows/ci.yml/badge.svg" alt="CI">
  </a>
  <img src="https://img.shields.io/badge/platform-macOS%20%7C%20Linux-blue" alt="Platform">
  <img src="https://img.shields.io/badge/shell-zsh-green" alt="Shell">
  <img src="https://img.shields.io/badge/theme-catppuccin%20mocha-cba6f7" alt="Theme">
  <img src="https://img.shields.io/badge/startup-%3C200ms-brightgreen" alt="Startup">
  <a href="LICENSE">
    <img src="https://img.shields.io/badge/license-MIT-yellow" alt="License">
  </a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/neovim-LazyVim-57A143?logo=neovim&logoColor=white" alt="Neovim">
  <img src="https://img.shields.io/badge/terminal-Ghostty-1a1b26" alt="Ghostty">
  <img src="https://img.shields.io/badge/multiplexer-tmux-1BB91F" alt="tmux">
  <img src="https://img.shields.io/badge/prompt-Starship-DD0B78?logo=starship&logoColor=white" alt="Starship">
</p>

---

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/kushrp/dotfiles/main/install.sh | bash
```

**Dry run** (see what would happen without changing anything):
```bash
curl -fsSL https://raw.githubusercontent.com/kushrp/dotfiles/main/install.sh | bash -s -- --dry-run
```

**Headless** (servers — skip GUI apps and fonts):
```bash
curl -fsSL https://raw.githubusercontent.com/kushrp/dotfiles/main/install.sh | bash -s -- --headless
```

## What You Get

| Layer | Tools |
|-------|-------|
| Shell | Zsh + Zinit + Starship + Atuin + zsh-autosuggestions + syntax-highlighting |
| Editor | Neovim (LazyVim) + avante.nvim (AI) + Supermaven (completion) |
| Terminal | Ghostty + tmux + sesh (session management) |
| Navigation | yazi + lazygit + fzf + zoxide + ripgrep + fd + ast-grep |
| Dev | mise (Python/Node) + direnv + just + watchexec + hyperfine |
| Git | delta (diffs) + difftastic (structural) + lazygit (TUI) |
| AI | llm CLI + avante.nvim + Supermaven + Atuin |
| CLI | bat + eza + dust + btop + procs + glow + thefuck |

**56 tools**, one consistent Catppuccin Mocha theme, sub-200ms shell startup.

## Design Principles

- **Catppuccin Mocha everywhere** — one colorscheme, zero visual inconsistency
- **Sub-200ms shell startup** — Zinit turbo-loading, no eager sources
- **Works offline** — no network calls after initial install
- **Idempotent** — run install anytime to update, never breaks state
- **No secrets in repo** — API keys via `~/.local/dotfiles.d/secrets.zsh`
- **Stow = truth** — every config managed by GNU Stow, nothing hand-placed

## Structure

```
dotfiles/
├── install.sh              # bootstrap entry point
├── Brewfile                # macOS packages
├── packages.txt            # Debian/Ubuntu packages
├── stow/
│   ├── zsh/.zshrc
│   ├── starship/.config/starship.toml
│   ├── tmux/.tmux.conf
│   ├── nvim/.config/nvim/  # LazyVim config
│   ├── ghostty/.config/ghostty/config
│   ├── yazi/.config/yazi/
│   ├── lazygit/.config/lazygit/config.yml
│   ├── atuin/.config/atuin/config.toml
│   ├── git/.gitconfig
│   ├── bat/.config/bat/config
│   ├── btop/.config/btop/btop.conf
│   └── mise/.config/mise/config.toml
├── scripts/
│   ├── dotfiles-learn      # interactive tutorial
│   ├── dotfiles-tips       # tip-of-the-day
│   └── dotfiles-update     # pull + re-stow
├── tips/tips.yaml          # curated tips
├── cheatsheet/cheatsheet.tsv
└── docs/
    ├── DAY-1.md            # survive
    ├── WEEK-1.md           # flow
    └── MONTH-1.md          # power
```

## Learning System

Built-in progressive learning — no memorization required:

```bash
dotfiles-learn    # interactive tutorial menu
dotfiles-tips     # random tip each shell session (never repeats)
```

| Tier | Focus | Timeline |
|------|-------|----------|
| Day 1 | Survive: open, save, quit, navigate | First session |
| Week 1 | Flow: text objects, telescope, git, LSP | First week |
| Month 1 | Power: macros, registers, AI, ast-grep | First month |

## Customization

Machine-specific config goes in `~/.local/dotfiles.d/`:

```bash
# ~/.local/dotfiles.d/work.zsh
export AWS_PROFILE="work"
alias bb="brazil-build"

# ~/.local/dotfiles.d/secrets.zsh
export ANTHROPIC_API_KEY="sk-ant-..."
```

These files are sourced at the end of `.zshrc` and never committed.

## Update

```bash
dotfiles-update   # pulls latest, re-stows everything
```

## Key Bindings

| Context | Key | Action |
|---------|-----|--------|
| Anywhere | `C-h/j/k/l` | Navigate panes (vim↔tmux) |
| Shell | `Ctrl-R` | Atuin fuzzy history |
| Shell | `Ctrl-T` | fzf file picker |
| tmux | `C-a T` | sesh session switcher |
| tmux | `C-a \|` / `C-a -` | split vertical / horizontal |
| nvim | `<leader>ff` | find files |
| nvim | `<leader>fg` | live grep |
| nvim | `<leader>gg` | lazygit |
| nvim | `<leader>aa` | AI chat (avante) |

## License

[MIT](LICENSE)
