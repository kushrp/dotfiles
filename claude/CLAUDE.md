# Global Claude Code instructions (kush)

These apply to every Claude Code session (symlinked to `~/.claude/CLAUDE.md`).
Project-level `CLAUDE.md` files always take precedence.

## Workflow

- **Never commit on `main`.** Each piece of work goes on its own branch, ideally
  in its own git worktree. Spin one up with `cc <name>` (see below) rather than
  switching branches in place.
- **Landing PRs:** in repos that use Graphite (e.g. ask-rogo), land via `gt`
  (`gt create` / `gt submit`), never a raw `git merge`/`git push` to main.
- **Parallel agents:** I run several Claude Code sessions at once (often as split
  panes in one tmux window). The agent dashboard (`ccd` / `prefix a`, or click
  the status-bar tally) lists them all and jumps between them. Keep changes
  scoped to the current worktree.

## Style

- Match the surrounding code's conventions; don't restate them.
- Comments only when the *why* is non-obvious (hidden constraint, workaround,
  deliberate tradeoff) — never narrate the change.
- Surface failures honestly: if tests fail or a step was skipped, say so.
- **Before finishing any `ask-rogo` code** (TS in `apps/backend`, `apps/rogo-agent`,
  `apps/frontend`, `packages/*`), run the `rogo-self-review` skill — the checklist of
  patterns Rogo reviewers most often flag (tenant scoping, error handling, reuse,
  naming, transactions, scope discipline) that lint doesn't catch. Full rulebook:
  vault note "What Rogo reviewers actually flag".

## Shell environment

- zsh with: mise (runtimes), starship, atuin, zoxide (`cd` is zoxide), fzf,
  eza/bat/delta, llm. `cheat` prints the full cheatsheet.
- Prefer `rg`/`fd` over `grep`/`find`; `bat` over `cat`; `eza` over `ls`.

## Second brain (canonical knowledge store)

- The Obsidian vault is the single canonical store for durable knowledge:
  compound learnings, brainstorms, plans, design decisions, and repo notes.
  Path: `~/Library/Mobile Documents/iCloud~md~obsidian/Documents/Kush's Vault/Kush's vault`;
  layout and workflows live in the `brain` skill (source: `~/Documents/second-brain/`).
- Decision (2026-06-10): repo-level knowledge stores (ask-rogo `docs/solutions`,
  `docs/brainstorms`, `docs/plans`) are retired. Do not recreate them or write
  durable docs into repos.
- Before design, brainstorm, plan, or compound work, run brain recall over
  `04 - Resources/Compound` so prior learnings and decisions surface first.
- When `/ce-compound` or any design skill produces a learning/brainstorm/plan
  doc, write it into the vault per the brain skill's "compound capture" section
  (scrub before writing). This overrides skill defaults that target repo `docs/` paths.
