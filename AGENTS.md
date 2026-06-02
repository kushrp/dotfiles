# AGENTS.md — protocol for AI-assisted setup of this repo

This file briefs an AI agent (Claude Code, Codex, Cursor, etc.) on how to
set up a new laptop with this dotfiles repo. The deterministic baseline is
`install.sh`; you (the agent) are expected to handle the 20% that the
script can't: cask adoption failures, App Store apps, secret entry,
1Password vault setup, OS defaults, and recovery from known footguns.

If you can run shell commands and edit files, follow this protocol. If you
can only generate text, output the equivalent commands as a runbook for the
human.

---

## 1. Mission

Get a brand-new Mac (or Linux box, once that's wired up) to:

- Have Homebrew + every CLI/cask in `Brewfile` installed.
- Have all dotfiles symlinked from this repo into `$HOME`.
- Have Ghostty themed (Tokyo Night), zsh fast (<200ms warm startup),
  Neovim launching LazyVim cleanly, Starship prompt rendering, fzf
  fuzzy-completion + history search working.
- Have `~/.extra` (gitignored, chmod 600) populated with the user's git
  identity and the secrets/tokens they actually use.
- Pass `verify_stack` in `install.sh` with zero failures.

If you can't get all of that, the deliverable is a precise list of what's
left and the exact commands the user needs to run.

---

## 2. Pre-conditions to verify before touching anything

| Check | How |
|---|---|
| macOS | `uname -s` returns `Darwin`. (Linux path is stubbed — see `linux/`.) |
| Xcode CLT | `xcode-select -p` exits 0. If not, `xcode-select --install` and **wait** for the GUI installer before continuing. |
| Network | `curl -fsI https://github.com` succeeds. |
| sudo available | The user is running interactively; cask installs that "adopt" existing `.app`s need sudo. |
| Existing apps in /Applications | `ls /Applications` — if Slack/Linear/Notion/Cursor/etc. are already there but **not** managed by brew, see Failure Mode #1 below. |

Do not run `install.sh` until all of these pass.

---

## 3. Phases (run in order)

`install.sh` already orchestrates these, but if you have to do it manually
or recover mid-flight, the order is:

1. **preflight** — OS + Xcode CLT + package manager detection.
2. **install_package_manager** — Homebrew (Mac) or apt/dnf/pacman (Linux).
3. **install_packages** — `brew bundle --file=Brewfile` (and `Brewfile.local` if present).
4. **install_bun** — `curl -fsSL https://bun.sh/install | bash` if missing.
5. **ensure_vim_dirs** — `~/.vim/{backups,swaps,undo}` real dirs + colors/syntax symlinks.
6. **symlink_dotfiles** — each entry in `DOTFILES_TO_LINK` from repo → `$HOME`.
7. **setup_ghostty** — `~/.config/ghostty/config` symlink.
8. **setup_starship** — `~/.config/starship.toml` symlink.
9. **setup_neovim** — `~/.config/nvim` symlink (LazyVim self-bootstraps on first `nvim`).
10. **setup_fzf_keybindings** — `$(brew --prefix)/opt/fzf/install --all --no-bash --no-fish --no-update-rc --xdg`.
11. **setup_extra** — if `~/.extra` is missing, copy from `.extra.example` and chmod 600.
12. **set_default_shell** — `chsh -s /bin/zsh` if not already zsh.
13. **apply_os_defaults** — opt-in (`--with-macos`).
14. **verify_stack** — every tool resolves, ghostty config parses, nvim launches.

Re-running any phase is safe; everything is idempotent.

---

## 4. Decision points — ask the user

These cannot be inferred from the environment. Ask before assuming.

- **git identity**: name + email for `~/.gitconfig.local` (written by
  `~/.extra`). If the user has multiple identities (work vs. personal),
  ask which goes in the global include; per-repo overrides handle the
  rest.
- **GitHub auth**: `gh auth login` must be run **interactively**. Walk the
  user through it. Default protocol: SSH. Default scope: `repo`,
  `read:org`, `gist`, `admin:public_key`.
- **1Password**: does the user have an account and want secrets there? If
  yes, `op signin`, then for each token they want to centralize, ask for
  the vault item path (`op://vault/item/field`). Update `~/.extra` to
  pull from `op read` instead of literal exports.
- **macOS defaults**: `.macos` is destructive and opinionated. Confirm
  before running, and note that some changes need a reboot.
- **Apps already on /Applications**: see Failure Mode #1.

---

## 5. Known failure modes + recovery

### #1. `brew bundle` cask adoption fails with "a terminal is required to read the password"

**Trigger:** a cask in `Brewfile` (e.g. `slack`, `linear`, `notion`,
`tailscale`, `claude`) is already in `/Applications` from a manual install.
Brew tries to "adopt" it by `chmod -R a+rX`, which needs sudo. In a
non-TTY context, sudo fails and brew **deletes the cask installation
metadata**. In at least one observed case, brew also **deleted
`/Applications/Cursor.app`** itself during failed rollback.

**Recovery:**

1. Re-cache sudo: `sudo -v`.
2. Re-run `brew bundle --file=Brewfile` in an actual TTY.
3. For any cask brew destructively removed, reinstall: `brew install --cask <name>`.
4. If a `/opt/homebrew/bin/<name>` symlink survives but points nowhere,
   `rm` it before retrying (e.g. the `cursor` binary).
5. As a safer alternative, run `./install.sh --no-casks` which only
   installs formulae and leaves apps alone.

**Prevention:** `install.sh` now pre-caches `sudo -v` if a TTY is
available. On fully fresh machines (apps not pre-installed), this
problem doesn't occur.

### #2. zsh starts but completion / autosuggestions are silent

Check, in order:

1. `command -v starship && command -v zoxide && command -v fzf` — if any
   missing, `brew install` it.
2. `ls /opt/homebrew/share/{zsh-autosuggestions,zsh-fast-syntax-highlighting,fzf-tab}` —
   files must exist.
3. `zsh -i -c 'echo $fpath'` — must include `/opt/homebrew/share/zsh/site-functions`.
4. `compaudit` — if it lists insecure dirs, `compaudit | xargs chmod g-w`.
5. `rm ~/.zcompdump && zsh -i -c 'compinit -i'` — rebuild the dump.

### #3. Neovim opens but plugins don't install

On first `nvim`, lazy.nvim clones itself, then triggers plugin install.
Symptoms: `:Lazy log` shows clone errors, or `:checkhealth` complains.

**Recovery:**

- `rm -rf ~/.local/share/nvim` and re-launch `nvim`. lazy.nvim will
  bootstrap fresh.
- `:LazyExtras` to confirm the language packs you want are enabled.
- `:Mason` then `:MasonInstall` for any LSPs that didn't auto-install
  (treesitter, typescript-language-server, etc.).

### #4. Ghostty config doesn't apply / shows default theme

1. `ghostty +validate-config --config-file=$HOME/.config/ghostty/config` —
   must exit 0. Inline comments after values are a common cause; move
   comments to their own lines.
2. Confirm the symlink: `readlink ~/.config/ghostty/config`.
3. Quit Ghostty fully (cmd+q) and relaunch — `cmd+shift+,` reload is
   sometimes insufficient for theme changes.

### #5. `git push` fails with `gpg failed to sign the data`

The committed `.gitconfig` sets `commit.gpgsign = false`. If you see
this, some other config is overriding it. Check:

```bash
git config --show-origin --get-all commit.gpgsign
```

Override per-repo with `git config commit.gpgsign false` or globally in
`~/.gitconfig.local`.

### #6. Cursor (`gh auth token`) returns empty, GITHUB_AUTH_TOKEN is unset

`~/.extra` falls back to a literal token if the gh keychain branch
returned empty. If even that is unset, run:

```bash
gh auth login        # interactive
exec zsh -l          # re-read ~/.extra
echo ${GITHUB_AUTH_TOKEN:0:7}
```

---

## 6. Verification checklist (run at the end)

```bash
# Shell
/usr/bin/time -p zsh -i -c exit 2>&1 | grep real      # < 200ms warm

# Tooling
for t in zsh git gh brew bun nvim tmux starship zoxide fzf rg fd bat eza \
         mise direnv atuin lazygit delta llm navi tldr pre-commit gitleaks; do
  command -v "$t" >/dev/null || echo "MISSING: $t"
done

# Pre-commit hooks installed + passing
( cd "$DOTFILES" && pre-commit run --all-files )

# Ghostty
ghostty +validate-config --config-file=$HOME/.config/ghostty/config

# Neovim — headless launch (LazyVim should bootstrap on first run)
nvim --headless '+qall'

# Git identity
git config --get user.name; git config --get user.email

# Tokens
echo ${GITHUB_AUTH_TOKEN:0:7}...

# Symlinks point at repo
for f in .zshrc .zprofile .gitconfig .config/nvim .config/ghostty/config .config/starship.toml; do
  printf '%-35s -> %s\n' "$f" "$(readlink "$HOME/$f")"
done
```

All groups must pass before declaring success.

### Pre-commit pipeline

This repo gates every commit with `.pre-commit-config.yaml` (installed by
`install.sh` via `pre-commit install`). If you commit on the user's behalf
and a hook fails, **fix the cause — do not `git commit --no-verify`**. The
hooks enforce: no secrets (gitleaks), no tracking of `.extra` /
`.gitconfig.local` / `Brewfile.local`, shellcheck-clean scripts, parseable
zsh / ghostty / nvim / toml / json / yaml configs. The same hooks run in
CI, so a bypass only defers the failure.

---

## 7. What NOT to do

- Don't commit `~/.extra`, `~/.gitconfig.local`, or `Brewfile.local`.
- Don't paste tokens into chat, commit messages, or `.zshrc` directly —
  the `~/.extra` indirection exists to keep them out of git. If a token
  has been exposed, **rotate it** and tell the user.
- Don't run `.macos` without confirmation. It is opinionated and some
  settings require reboot.
- Don't `bun install` or otherwise mutate the user's workspaces during
  laptop setup — install only what's in `Brewfile`.
- Don't fork the plugin sourcing in `.zshrc` between machines. If a path
  varies, fix `BREW_PREFIX` resolution at the top, not the individual
  source lines.
- Don't widen permission allowlists in `.claude/settings.json` for
  mutating commands. See the `/fewer-permission-prompts` skill.
