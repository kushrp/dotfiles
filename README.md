# dotfiles

Run `~/bin/mac-config status` on a configured Mac to check the repositories and agent runtime.
Use the setup steps below for the first installation.

This repo shares shell settings, agent instructions, and tool definitions across Macs.
The configuration runtime uses the `codex/mac-config-sync` branch in this repo and
[Rogo-Technologies/kush-rogo-skills](https://github.com/Rogo-Technologies/kush-rogo-skills).
The separate `install.sh` installs the full workstation package set.

## Set up shared configuration

Start with Git, Python 3.11 or later, and GitHub access on this Mac.
The branch must exist in both remotes before you use the remote setup commands.
Sign in to each agent application on each device.

1. Clone the installer branch into an unused directory:

   ```bash
   git clone --branch codex/mac-config-sync https://github.com/kushrp/dotfiles.git ~/Documents/mac-config-bootstrap
   ```

2. Create the runtime clones and install the shared configuration:

   ```bash
   python3 ~/Documents/mac-config-bootstrap/bin/mac-config init \
     --dotfiles-source https://github.com/kushrp/dotfiles.git \
     --agents-source git@github.com:Rogo-Technologies/kush-rogo-skills.git \
     --branch codex/mac-config-sync
   ```

3. Check the installed links:

   ```bash
   ~/bin/mac-config status
   ```

4. Install the shared shell programs after Homebrew is available:

   ```bash
   ~/bin/mac-config setup-tools
   ```

5. Apply the configuration again after the programs are available:

   ```bash
   ~/bin/mac-config install --apply
   exec zsh -l
   ```

`init` writes its repository configuration to `~/.local/share/mac-config/config.json`.
It creates independent clones under `~/.local/share/mac-config/repos/dotfiles` and
`~/.local/share/mac-config/repos/agents`. The `~/.agents` symlink points to the agents clone.

The installer backs up replaced configuration under
`~/.local/share/mac-config/backups/<timestamp>/`.
Conflicting agent files have separate backups under the agents clone's `.skill-sync-backup/`.
Existing regular `.zshrc` and `.zprofile` files become `.zshrc.local` and `.zprofile.local`.
If a different local override already exists, reconcile the two files before installing.

`setup-tools` uses `Brewfile.sync` and installs the pinned Node, Bun, and pnpm versions.
It also prepares the pinned Understand Anything checkout.
It requires Homebrew and runs for the current user only.

## Receive and publish changes

Run this on either configured Mac to receive committed updates:

```bash
~/bin/mac-config sync
```

`sync` fetches both configured branches and accepts fast-forward updates only.
Local changes, an unexpected branch, or diverged history stop synchronization.
After receiving updates, it applies the links, generated agents, hooks, and tool definitions.
`status` checks local repository and runtime state; it does not fetch remote updates or test service login.
After plugin setup, synchronization also applies plugin pins, and status checks their native installation.

Enable receiving every five minutes with:

```bash
~/bin/mac-config enable-auto-sync
```

The macOS launch agent also runs when loaded. Its logs are
`~/.local/share/mac-config/logs/sync.log` and
`~/.local/share/mac-config/logs/sync-error.log`.
Background receiving does not publish local edits.

Edit the runtime source, review the diff, and publish explicit repository-relative paths:

```bash
$EDITOR ~/.local/share/mac-config/repos/dotfiles/.aliases
git -C ~/.local/share/mac-config/repos/dotfiles diff -- .aliases
~/bin/mac-config publish dotfiles --message "Add a shell alias" .aliases
```

For a skill, name its source directory:

```bash
~/bin/mac-config publish agents --message "Update the review skill" skills/rogo-review
```

`publish` requires `gitleaks`, rejects existing staged changes, and scans the selected changes before committing.
It pushes to the configured branch. Publishing the entire repository with `.` is rejected.
Publishing requires the local commit to equal the fetched remote commit.
Prior local commits or new remote commits must be reconciled before publishing.

## Shared tools and plugins

| Source | Purpose |
| --- | --- |
| `Brewfile.sync` | Shared shell programs installed by `mac-config setup-tools`. |
| `agent-tools.json` | Model Context Protocol (MCP) definitions for Claude Code, Codex, and Grok. |
| `agent-plugins.json` | Pinned native plugin versions and marketplace commits for Claude Code and Grok. |
| Agents repo: `laptop/skill-sources.json` | Names and source paths for shared skills. |
| Agents repo: `laptop/vendor-skills.lock.json` | File hashes for the bundled vendor skill snapshots. |

Preview tool definitions or check whether local definitions match the manifest:

```bash
python3 ~/.local/share/mac-config/repos/dotfiles/bin/sync-agent-tools.py
python3 ~/.local/share/mac-config/repos/dotfiles/bin/sync-agent-tools.py --check
```

Use `--apply` to write changes. After reviewing a conflicting named server, use
`--apply --replace-existing` to back it up and adopt the manifest definition.
The script also accepts `--home`, `--manifest`, and `--hostname`.

The `brain-vault` server applies only to the laptop host `rogo-CDVHHFGXPD`.
Both required paths must exist on that laptop:

- `~/Documents/second-brain/brain-mcp-recall.py`
- `~/Library/Mobile Documents/iCloud~md~obsidian/Documents/Kush's Vault/Kush's vault`

The manifest skips this server on other hosts. The vault stays on the laptop.
Codex's desktop computer-use integration remains managed by the desktop app.

Install Claude Code and Grok before setting up their native plugins:

```bash
~/bin/mac-config setup-plugins
```

Successful setup enables plugin updates during later `sync` calls and plugin checks during `status` calls.
If setup reports conflicting Grok copies, review the paths before running `~/bin/mac-config setup-plugins --adopt`.

For a standalone preview, installation, or check, run these commands from the dotfiles runtime clone:

```bash
cd ~/.local/share/mac-config/repos/dotfiles
python3 bin/sync-agent-plugins.py
python3 bin/sync-agent-plugins.py --apply
python3 bin/sync-agent-plugins.py --check
```

Running the script without flags previews changes. `--apply` installs the manifest pins through the native plugin commands.
If the preview reports conflicting Grok copies, review the paths before using `--apply --adopt`.
That option moves those copies into `~/.local/state/mac-config/plugin-backups/<timestamp>/`.
The script also accepts `--home` and `--manifest`; its default manifest is this repo's `agent-plugins.json`.
Start new Claude Code and Grok sessions after installation.

GitHub credentials, agent login, service authorization, and local secrets stay on each device.
The manifests share definitions and versions. A configuration check does not prove that a service accepts requests.

## Preview or repair installation

```bash
~/bin/mac-config install
~/bin/mac-config install --apply
```

The first command previews links. Installation stops when an unmanaged destination conflicts.
Review that destination before running `~/bin/mac-config install --apply --adopt` to back it up and replace it.
Use `~/bin/mac-config status` after repair.

## Full workstation installation

Use `install.sh` for a fresh workstation's full package and application setup.
Run it before `mac-config init` so the final links point into the shared runtime clones.
This path also requires macOS and the Xcode Command Line Tools.

```bash
git clone https://github.com/kushrp/dotfiles.git ~/Documents/dotfiles
cd ~/Documents/dotfiles
./install.sh
```

The installer performs these groups of work:

1. Install Homebrew, the `Brewfile` package set, and Bun.
2. Back up replaced dotfiles to `~/.dotfiles-backup/<timestamp>/` and create configuration links.
3. Configure the shell, editors, tmux plugins, and agent runtime.
4. Seed `~/.extra`, install pre-commit hooks, and set zsh as the login shell.
5. Verify the installed programs and report failures.

Finish local identity and authentication setup:

```bash
$EDITOR ~/.extra
gh auth login
exec zsh -l
```

`--no-casks` installs formulae without adopting existing applications.
`--no-brew` skips package installation when you are working on configuration.
The installer leaves an existing `~/.extra` in place.

Review `.macos` before applying its system defaults. Some settings require a restart.
After choosing to apply those settings, run:

```bash
./install.sh --with-macos -y
```

## Local secrets and overrides

`~/.extra` holds local tokens and is excluded from Git.
The full installer creates it from `.extra.example` with mode `600`.
The shell reads it after the shared settings.
Use `~/.gitconfig.local` for local Git identity and settings.
Use `.zshrc.local` and `.zprofile.local` for settings that differ between Macs.

The GitHub environment variable can read the token from the local keychain:

```bash
# ~/.extra
if command -v gh >/dev/null 2>&1; then
  _gh_token="$(gh auth token 2>/dev/null)"
  [ -n "$_gh_token" ] && export GITHUB_AUTH_TOKEN="$_gh_token"
fi
```

Run `gh auth login` to replace that token. Reload the shell to use the new value.
Store personal package additions in the ignored `Brewfile.local`.
Install those additions with `brew bundle --file=Brewfile.local`.

## Repository layout

| Path | Purpose |
| --- | --- |
| `bin/mac-config` | Initialize runtime clones, install links, receive updates, and publish named paths. |
| `install.sh`, `bootstrap.sh` | Full workstation installer and its compatibility entry point. |
| `Brewfile` | Full macOS package and application set. |
| `.zshrc`, `.zprofile`, `.zshenv` | Shared zsh configuration. |
| `.aliases`, `.functions`, `.exports` | Shell aliases, functions, and environment defaults. |
| `.bash_profile`, `.bashrc`, `.bash_prompt` | Bash configuration. |
| `.gitconfig`, `.gitattributes` | Shared Git configuration. |
| `claude/CLAUDE.md`, `claude/forbidden.md` | Shared agent instructions and writing rules. |
| `.config/ghostty/`, `.config/starship.toml` | Terminal appearance and prompt configuration. |
| `.config/nvim/`, `.vimrc`, `.vim/` | Neovim and Vim configuration. |
| `.tmux.conf`, `.tmux-cheatsheet.md` | tmux configuration and its cheatsheet. |
| `.config/atuin/config.toml`, `.config/zsh/tips.txt` | History configuration and shell tips. |
| `.pre-commit-config.yaml`, `.gitleaks.toml` | Validation hooks and secret-scanner rules. |
| `AGENTS.md` | Agent instructions for full workstation setup. |
| `.macos`, `init/`, `linux/` | Optional system defaults, app snapshots, and Linux package lists. |

## Validate changes

The full installer installs the repository's pre-commit hooks.
Run all configured checks from the repository:

```bash
pre-commit run --all-files
```

The hooks check secrets, forbidden local files, shell syntax, configuration parsing, and file hygiene.
Fix failed hooks before committing. The repository also runs checks in GitHub Actions.
`mac-config publish` performs a staged secret scan but does not install pre-commit hooks.

## Shell and editor shortcuts

| Command or key | Action |
| --- | --- |
| `cheat` or `keys` | Show the shell cheatsheet and live aliases. |
| `coach`, `learn` | Check feature usage or start the interactive tour. |
| `Ctrl-G` | Insert an editable command from navi. |
| `help <cmd>` | Show tldr command examples. |
| tmux `prefix C-h`, `prefix ?` | Open the cheatsheet or show bindings. |
| Neovim `<space>?`, `<space>uc` | Show keymaps or open the written cheatsheet. |
| `ai <description>`, `explain <cmd>` | Suggest or explain a shell command through `llm`. |

The shell AI helpers need an Anthropic key in `~/.extra` or `llm keys set anthropic`.
`Ctrl-X Ctrl-A` converts a typed description into a command.
Shell tips live in `~/.config/zsh/tips.txt`.

Use `cc <name>` to start Claude Code in a worktree and tmux window.
The default repository is ask-rogo; set `CC_REPO` to choose another repository.
`CC_FLAGS= cc <name>` clears the helper's default `--dangerously-skip-permissions` option.
Use `ccls` to list worktrees, or `ccd` and tmux `prefix a` to open the agent dashboard.

Review work before running `ccland` to submit a pull request.
It uses Graphite in Graphite repositories and GitHub commands elsewhere.
After the pull request merges, `ccrm <name>` removes its worktree and branch.
The status hooks report waiting, working, and finished agents in tmux.

## Troubleshooting

| Symptom | Action |
| --- | --- |
| Synchronization reports local changes | Inspect `git status` in the named runtime clone. Publish intended changes or reconcile them before receiving. |
| Skill or generated-agent drift | Run `mac-config install` to preview repairs. Apply them and run `mac-config status`. |
| Cask adoption requests a terminal | Run the full installer in an interactive terminal, or use `./install.sh --no-casks` to preserve existing applications. |
| A cask fails during the full install | Inspect the named package with `brew bundle --file=Brewfile`; check for a renamed cask. |
| Git reports a signing failure | Run `git config --show-origin --get-all commit.gpgsign` and correct the responsible local setting. |
| A GitHub token is unavailable | Run `gh auth status`, sign in if needed, and reload with `exec zsh -l`. |

Homebrew adoption failures can remove an existing application during rollback.
Use `--no-casks` when preserving manually installed applications matters.

The shell caches initialization scripts under `~/.cache/zsh-init/` and limits full completion initialization to once per day.
Measure startup after configuration changes:

```bash
for i in 1 2 3; do /usr/bin/time -p zsh -i -c exit; done
```

Linux package lists live in [linux/README.md](linux/README.md).
Ghostty installation, fonts, and desktop defaults still need Linux-specific setup.
The original dotfiles came from [mathiasbynens/dotfiles](https://github.com/mathiasbynens/dotfiles).
