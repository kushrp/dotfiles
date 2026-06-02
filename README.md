# dotfiles

One-shot, idempotent dotfiles repo. Clone on any Mac (or, soon, any
Linux box), run `./install.sh`, get a working environment: Homebrew,
Ghostty, zsh, git, the editor and shell config, plus the GUI apps I rely
on day to day. Re-run it any time — it backs up before overwriting and
never silently clobbers a file.

Forked from [mathiasbynens/dotfiles](https://github.com/mathiasbynens/dotfiles),
then rewritten around an OS-aware `install.sh`, a declarative `Brewfile`,
zsh as the primary shell, and `~/.extra` for secrets that should never
land in git.

---

## Quick start (new laptop)

```bash
# macOS will prompt for Xcode Command Line Tools the first time `git` runs.
git clone https://github.com/kushrp/dotfiles.git ~/Documents/dotfiles
cd ~/Documents/dotfiles
./install.sh
```

That single command:

1. Verifies macOS + Xcode CLT are present.
2. Installs Homebrew (non-interactively) if missing.
3. Runs `brew bundle` against `Brewfile` — CLI tools, Ghostty, fonts,
   the GUI apps in my default kit. Also runs `Brewfile.local` if you've
   created one for personal extras.
4. Installs Bun via the official installer.
5. Backs up existing dotfiles to `~/.dotfiles-backup/<timestamp>/`.
6. Symlinks every shell/tool config into `$HOME` (zsh, git, vim, ghostty,
   starship, neovim/LazyVim, tmux, atuin, llm, zsh tips).
7. Clones tpm and installs tmux plugins; installs the `llm-anthropic` plugin.
8. Sets `node@lts` as the mise global and opts mise into reading `.nvmrc`.
9. Installs the pre-commit hooks (secret scan + syntax/parse checks) into
   the repo's `.git/hooks`.
10. Seeds `~/.extra` from `.extra.example` (the template for secrets +
    git identity).
11. Sets zsh as the login shell.
12. Verifies the whole stack (`verify_stack`) and prints a numbered list of
    any failures.

After it finishes:

```bash
$EDITOR ~/.extra        # set git identity + tokens
gh auth login           # populates the keychain that .extra reads from
exec zsh -l             # reload the shell
```

Apply macOS system defaults (`.macos` — opinionated and destructive)
when you're ready:

```bash
./install.sh --with-macos -y
```

---

## Repo layout

| Path | What it is |
| --- | --- |
| `install.sh` | One-shot installer. OS-aware, idempotent, collects failures, prints a summary. |
| `bootstrap.sh` | Backwards-compatible shim; just execs `install.sh`. |
| `Brewfile` | Declarative list of brew formulae + casks for macOS. |
| `Brewfile.local` | (Gitignored.) Personal additions on this machine. Optional. |
| `.zshrc`, `.zprofile` | zsh login + interactive config. Sources `.aliases`, `.functions`, `.exports`, `.extra`. |
| `.bash_profile`, `.bashrc`, `.bash_prompt` | bash equivalents, kept for bash sessions. |
| `.aliases` | Shell aliases (`g=git`, `..`, `update`, etc.) shared between bash and zsh. |
| `.functions` | Shell functions (`mkd`, `targz`, `server`, `o`, ...). |
| `.exports` | Env exports common to both shells. |
| `.gitconfig`, `.gitattributes` | Global git settings. User identity is **not** here — it lives in `~/.extra` so the repo can be shared. |
| `.vimrc`, `.vim/` | vim config + storage dirs (backups/swaps/undo). |
| `.tmux.conf`, `.screenrc`, `.inputrc`, `.curlrc`, `.wgetrc`, `.editorconfig` | Tool configs. |
| `.config/ghostty/config` | Ghostty terminal config (Tokyo Night, JetBrainsMono Nerd Font, perf-tuned). |
| `.config/starship.toml` | Starship prompt config — Tokyo Night palette, git/lang context. |
| `.config/nvim/` | Neovim config built on LazyVim. Tokyo Night theme, which-key cheatsheet, telescope/treesitter/lsp/mason wired up. `<space>?` opens `CHEATSHEET.md`. |
| `.config/nvim/CHEATSHEET.md` | Written cheatsheet for Neovim keymaps; open in-editor with `<space>uc`. |
| `.tmux.conf`, `.tmux-cheatsheet.md` | tmux config (Tokyo Night, tpm plugins, popups) + the `prefix C-h` cheatsheet popup. |
| `.config/zsh/tips.txt` | Rotating tip-of-the-day lines printed on new shells. Grow it as you learn. |
| `.config/atuin/config.toml` | atuin history config (perf-tuned: no startup network check). |
| `.pre-commit-config.yaml` | Pre-commit hook pipeline (secret scan + syntax/parse checks). |
| `.gitleaks.toml` | gitleaks rules + allowlist for the secret scanner. |
| `.github/workflows/install.yml` | CI: runs `install.sh`, pre-commit, and gitleaks on macOS + Linux runners. |
| `AGENTS.md` | Protocol for an AI agent (Claude Code/Codex/Cursor) to set up a fresh laptop using this repo. |
| `.extra.example` | Template for `~/.extra`. Copy to `~/.extra` and fill in. |
| `.macos` | Long script of `defaults write` calls. Opt-in via `install.sh --with-macos`. |
| `brew.sh` | Legacy upstream brew script. Superseded by `Brewfile`; kept for reference. |
| `init/` | App config snapshots (Sublime Text prefs, iTerm/Terminal color schemes). |
| `linux/` | Per-distro package lists for future Linux support. See `linux/README.md`. |

---

## How secrets are layered in

Tokens, API keys, and git identity live in **`~/.extra`**, which is:

- Gitignored at the repo level (`.gitignore` includes `.extra`).
- Created by `install.sh` from `.extra.example` on first run, with
  `chmod 600`.
- Sourced **last** by both `.zshrc` and `.bash_profile`, so anything
  defined there overrides anything in the committed dotfiles.

The pattern for the GitHub token specifically is:

```bash
# ~/.extra
if command -v gh >/dev/null 2>&1; then
  _gh_token="$(gh auth token 2>/dev/null)"
  [ -n "$_gh_token" ] && export GITHUB_AUTH_TOKEN="$_gh_token"
fi
```

`gh` keeps the token in the macOS keychain. Rotating it via `gh auth
login` automatically refreshes the env var on next shell start — no need
to edit any file. Literal tokens (`ANTHROPIC_API_KEY`, etc.) can also be
exported from `~/.extra` for tools that can't read the keychain.

---

## Pre-commit safety net

`install.sh` runs `pre-commit install`, so every commit to this repo is
gated by `.pre-commit-config.yaml`. The hooks make it hard to ever leak a
secret or commit a broken config:

- **gitleaks** — scans staged content for real secrets (tokens, keys).
  Allowlist + custom rules in `.gitleaks.toml`.
- **block-secret-files** — hard-fails if `.extra`, `.gitconfig.local`, or
  `Brewfile.local` are ever staged (even with `git add -f`).
- **no-placeholder-tokens-elsewhere** — `ghp_xxxx…`-style placeholders are
  only allowed in `.extra.example`; anywhere else fails.
- **shellcheck** — lints `install.sh` / `bootstrap.sh` / `brew.sh`.
- **zsh -n** — parse-checks `.zshrc` / `.zprofile`.
- **ghostty +validate-config**, **nvim --headless**, **brew bundle list**,
  **check-toml/json/yaml** — every config file must parse.
- Standard hygiene: trailing whitespace, EOF newline, merge-conflict
  markers, large files, broken symlinks.

Run them all manually any time:

```bash
pre-commit run --all-files
```

The same hooks run in CI (`.github/workflows/install.yml`) on every push,
plus a full-history gitleaks scan — so even a `--no-verify` local bypass
gets caught before merge.

Bypass a single hook when you really mean it: `SKIP=hook-id git commit …`.

---

## Learning & discoverability

The setup is built to teach you as you use it, and to keep a cheatsheet one
keystroke away everywhere:

- **`cheat`** (alias `keys`) — colorized cheatsheet of every key, helper, and
  your live aliases. Type it anytime.
- **Tip of the day** — each new shell prints one rotating tip from
  `~/.config/zsh/tips.txt`. Add a line whenever you learn something.
- **`zsh-you-should-use`** — when you type a command that has an alias, it
  reminds you of the alias afterward, so you learn your own shortcuts.
- **`Ctrl-G` (navi)** — interactive, fuzzy cheatsheet that inserts an
  *editable* command at the prompt. Add cheats under `~/.local/share/navi/`.
- **`help <cmd>` (tldr/tealdeer)** — real-example man pages instead of walls of text.
- **tmux** — the status bar always shows `⌃a ? = keys  ⌃a ⌃h = cheatsheet`;
  `prefix C-h` opens the curated popup, `prefix ?` lists every binding.
- **Neovim** — press `<space>` and wait: the which-key panel *is* the live
  cheatsheet. `<space>?` shows all keymaps, `<space>uc` opens the written one.
  The start screen (snacks dashboard) lists the top keys every launch.
- **AI in the shell** — `ai <description>` suggests a command, `explain <cmd>`
  explains one, `Ctrl-X Ctrl-A` turns the typed line into a command, and
  `… | llm '…'` pipes anything to Claude. Backed by `llm` + `llm-anthropic`
  (set `ANTHROPIC_API_KEY` in `~/.extra` or run `llm keys set anthropic`).

## Parallel Claude Code agents

Run many agents at once, each isolated, and see/control them from one place:

- **`cc <name> [prompt]`** — spawn a Claude agent in its own git worktree +
  tmux window (native `claude --worktree`; branches off main, never merges, so
  it's Graphite-safe). `ccls` lists them, `ccrm <name>` removes one.
- **`ccd` / `prefix A`** — the agent dashboard: every session/window with a
  live output preview + git status, sorted so a blocked agent floats to the
  top. `enter` jump · `^x` kill · `^g` lazygit · `^n` new (type a name first)
  · `^r` refresh.
- **Status at a glance** — a Claude hook (`cc-status.sh`) tags each window
  ⏸ waiting-for-you / 🤖 working / ✅ done; the tmux window list shows the glyph
  and the status bar tallies them live (`cc-agent-count`). A desktop
  notification fires when an agent needs you or finishes.
- **`prefix T`** (sesh) — fuzzy-jump between agent sessions/worktrees.

## Learning it (coach + tour)

The setup teaches itself:

- **`coach`** — a scorecard of the power-features, marking what you've used and
  nudging what you haven't (a `preexec` hook tracks usage automatically).
- **`learn`** — an interactive, paced tour: each feature explained with a
  command to try, marked off as you go.
- **Tip-of-the-day** — every new shell nudges one feature you haven't tried yet
  (falls back to random tips once you've used them all).

## Shell startup speed

Warm `zsh` startup is ~**0.2s** despite loading mise, starship, atuin,
direnv, zoxide, fzf-tab, autosuggestions, and syntax highlighting. Two
tricks keep it fast:

- **Init-script caching** (`.zshrc` section 0): the output of
  `starship init`, `mise activate`, `zoxide init`, `atuin init`, and
  `direnv hook` is cached under `~/.cache/zsh-init/` and re-sourced
  instead of forking each binary on every shell. Caches auto-regenerate
  when the tool binary or `.zshrc` changes.
- **Daily `compinit`** — the slow completion-security scan runs at most
  once every 24h; other starts read the cached dump.

To re-profile after changes: `for i in 1 2 3; do /usr/bin/time -p zsh -i -c exit; done`.

---

## Re-running safely

`install.sh` is safe to run repeatedly. On each run it:

- Skips Homebrew if `brew` is already on `$PATH`.
- Skips already-installed brew formulae/casks (that's `brew bundle`'s
  default behavior).
- Skips dotfiles that are already correctly symlinked.
- Backs up anything it needs to replace to
  `~/.dotfiles-backup/<timestamp>/`.
- Leaves `~/.extra` alone if it already exists.
- Skips `.macos` unless you pass `--with-macos`.

Use `--no-brew` to skip the brew step when iterating on shell config.

---

## Adding your own things

- **A new dependency on every machine** → add to `Brewfile`, commit.
- **A dependency only on this machine** → create `Brewfile.local`
  (gitignored), `brew bundle --file=Brewfile.local`.
- **A new secret / token** → add an `export` to `~/.extra`.
- **A new shell alias or function** → add to `.aliases` / `.functions`
  (used by both bash and zsh), commit.
- **A new dotfile to link** → add the filename to `DOTFILES_TO_LINK` in
  `install.sh`, commit. Keep the list explicit so we don't accidentally
  link `.ssh/`, `.gnupg/`, etc.

---

## Linux support (in progress)

`install.sh` already branches on `$OS` (`macos` vs `linux`) and picks
the right package manager (`apt`/`dnf`/`pacman`). Starter package lists
are in `linux/packages.<mgr>.txt`. To finish:

- Add a Ghostty install path (`.deb`/`.rpm`/source).
- Replace `.macos` for Linux desktop environments (or skip).
- Pick a font install path.

See `linux/README.md` for details.

---

## Troubleshooting

- **`brew bundle` failed on casks with "a terminal is required to read
  the password"** — happens on a machine where the apps were already
  installed *outside* brew. Brew tries to "adopt" the existing `.app`
  by `chmod`ing it, which needs sudo. Two ways out:
  - Run the installer in a real TTY (not via `nohup`/CI) — `install.sh`
    pre-caches `sudo -v` and the casks will install.
  - Run with `./install.sh --no-casks` to install formulae only.
  - **Caveat:** if brew fails to adopt a cask, it can *delete the
    existing `.app`* (this happened to Cursor during early testing).
    On a known-clean machine, prefer letting brew install everything
    from scratch; on a populated machine, use `--no-casks`.
- **`brew bundle` failed on a single cask** — re-run `install.sh`; the
  rest of the steps will continue. Or `brew bundle --file=Brewfile`
  manually to see the failing line. Common cause: a cask was renamed
  upstream (e.g. `linear-linear` → `linear`).
- **Commits fail with `gpg failed to sign the data`** — this repo sets
  `commit.gpgsign = false`. If you set up signing manually somewhere
  else, override in `~/.extra` or per-repo.
- **`git status` shows weird unicode filename issues on macOS** —
  `.gitconfig` already sets `core.precomposeunicode = false`.
- **Symlinks point to the wrong location** — you ran `install.sh` from a
  moved clone. Delete the broken symlink and re-run from the new
  location.
- **`~/.extra` is sourced but a token isn't picked up** — confirm with
  `echo $GITHUB_AUTH_TOKEN`. If empty, check `gh auth status` and
  re-run `exec zsh -l`.

---

## What changed vs. the upstream fork

- `install.sh` replaces `bootstrap.sh` (kept as a shim) with idempotent
  symlinks, OS detection, failure collection, and a backup-before-clobber
  policy.
- `Brewfile` replaces the legacy `brew.sh` (still kept around) and uses
  modern formulae/cask names. The CTF-tool list is gone.
- zsh is treated as the primary shell. `.zshrc` + `.zprofile` are added
  and source the shared `.aliases` / `.functions` / `.exports` / `.extra`.
- Full shell stack: `zsh-autosuggestions`, `zsh-fast-syntax-highlighting`,
  `fzf` + `fzf-tab` (fuzzy tab + Ctrl-R history), `starship` prompt,
  `zoxide` (smart `cd`). Lazy-loaded `nvm` so warm shell startup is ~100ms.
- Ghostty themed Tokyo Night with JetBrainsMono Nerd Font + ligatures.
- Neovim config built on LazyVim, themed to match, with a `<space>?`
  cheatsheet binding and which-key as the live menu.
- `.gitconfig` no longer hardcodes `commit.gpgsign = true` — too easy to
  break commits on a fresh machine without a key.
- `~/.extra` is a real file with a real template, not a vague README
  mention. Identity + tokens live there.
- `AGENTS.md` brief for AI-assisted setup (Claude Code / Codex / Cursor).
- `linux/` directory + OS detection scaffolding for future Linux support.
