# Global Claude Code instructions (kush)

These apply to every Claude Code session (symlinked to `~/.claude/CLAUDE.md`).
Project-level `CLAUDE.md` files always take precedence.

## Workflow

- **Never commit on `main`.** Each piece of work goes on its own branch, ideally
  in its own git worktree. Spin one up with `cc <name>` (see below) rather than
  switching branches in place.
- **Landing PRs:** in repos that use Graphite (e.g. ask-rogo), land via `gt`
  (`gt create` / `gt submit`), never a raw `git merge`/`git push` to main.
- **Parallel agents:** I run several Claude Code sessions at once, each in its
  own worktree (`cc`), and jump between their tmux sessions with `sesh`
  (`prefix T`). Keep changes scoped to the current worktree.

## Style

- Match the surrounding code's conventions; don't restate them.
- Comments only when the *why* is non-obvious (hidden constraint, workaround,
  deliberate tradeoff) — never narrate the change.
- Surface failures honestly: if tests fail or a step was skipped, say so.

## Shell environment

- zsh with: mise (runtimes), starship, atuin, zoxide (`cd` is zoxide), fzf,
  eza/bat/delta, llm. `cheat` prints the full cheatsheet.
- Prefer `rg`/`fd` over `grep`/`find`; `bat` over `cat`; `eza` over `ls`.
