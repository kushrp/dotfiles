# Global Claude Code instructions (kush)

These apply to every Claude Code session (symlinked to `~/.claude/CLAUDE.md`,
and to `~/.codex/AGENTS.md` + `~/.config/opencode/AGENTS.md` so Codex and
opencode read the same rules). Project-level files always take precedence.

## Workflow

- **Never commit on `main`.** Each piece of work goes on its own branch, ideally
  in its own git worktree, rather than switching branches in place.
- **Landing PRs:** in repos that use Graphite (e.g. ask-rogo), land via `gt`
  (`gt create` / `gt submit`), never a raw `git merge`/`git push` to main.
- **Stacking PRs:** split logically by theme. No churn: never add code or files
  a later PR in the stack deletes — no stopgaps or scaffolding you then remove
  (e.g. a "derive it for now, delete once the real path lands" helper). If a
  later layer supersedes an approach, restructure or reorder so each PR uses the
  final approach from the start; a reviewer of an early PR must never see a file
  the tip doesn't have. Fix things in place. Keep UI and back-end changes in
  separate PRs. Order the stack so it reads as one story (foundation first).
- **PR descriptions (always write and keep current).** Every PR gets a real
  description — never leave it to the bare commit subject or empty (`gt submit
  --no-edit` seeds it from the commit body; that is a starting point, not the
  finished description). On create, cover: what changed and why, this layer's
  role in the stack, testing/verification actually done, and reviewer-relevant
  caveats or deferred follow-ups. On update, whenever the diff changes materially
  (new commits, scope change, review fixes), refresh the description so it always
  matches the current state. Writing/updating a PR's own description is authorized
  and expected — it is NOT the same as replying to human reviewers or posting
  comments, which I still only draft for you. Use `gh pr edit <n> --body` (or
  `gt submit --edit`); `gh pr edit` is not gated by the pre-push hook.
- **Parallel agents:** I run several Claude Code sessions at once (often as split
  panes in one tmux window). The agent dashboard (`ccd` / `prefix a`, or click
  the status-bar tally) lists them all and jumps between them. Keep changes
  scoped to the current worktree.
- **Pre-push review gate (HARD).** Every push of code (`gt submit`/`gt create`/
  `git push`) goes through the `rogo-ts-effect-reviewer` agent first — no
  exceptions, no self-certifying. Dispatch it over the diff the push introduces
  (Claude: `Agent` tool, `subagent_type: rogo-ts-effect-reviewer`; Codex: the
  matching agent in `~/.codex/agents/`). It reads the live `ts-code-smells` /
  `rogo-self-review` rulebooks and returns `VERDICT: PASS | BLOCK`. On BLOCK, fix
  every blocking finding **at the source** and re-dispatch until PASS — never
  touch the gate marker to bypass a BLOCK. The `require-smell-review-before-push.sh`
  PreToolUse hook enforces this: it denies the push until a per-commit marker
  exists, and the marker is only legitimate after a PASS. New commits invalidate
  the marker, so every push of new code gets a fresh review. The reviewer's bar
  is the rulebooks plus: no un-narrowed `unknown`, no raw/untyped errors, no
  stack churn/stopgaps, tenant scoping, fix-generated-output-at-source.

## Style

- Match the surrounding code's conventions; don't restate them.
- Comments only when the _why_ is non-obvious (hidden constraint, workaround,
  deliberate tradeoff) — never narrate the change.
- Surface failures honestly: if tests fail or a step was skipped, say so.
- **Fix generated output at the source, keep it human-readable.** Model-authored
  output shown to users (memory docs, summaries, etc.) must be clean and
  human-readable — fix the generator (the prompt) so the data is right for every
  consumer, don't band-aid it by stripping/reformatting at one render layer. A
  render-layer fix only hides it on that surface and turns into regex whack-a-mole;
  a thin deterministic backstop is fine, but the source is the real fix.
- **Never push code with smells.** It must be clean by best-practice standards
  before any push. Two I get burned on: (1) `unknown` is a smell unless it's an
  input boundary you immediately narrow (catch binding, untrusted payload) —
  never leave it in an Effect error channel, a return type, or a typed-error
  payload; (2) raw/untyped errors are bad — model failures as typed/tagged errors
  (Effect `Schema.TaggedError`, or specific Nest exceptions), never throw or
  surface a bare `Error`, and the error channel lists specific tags, not `unknown`.
  Keep the `rogo-review-rulebook` (the canonical rules that `ts-code-smells` and
  `rogo-self-review` now load) current with authoritative best practices: refresh
  from online sources, don't rely on memory alone.
- **Before finishing any `ask-rogo` code** (TS in `apps/backend`, `apps/rogo-agent`,
  `apps/frontend`, `packages/*`), run the `rogo-self-review` skill — the checklist of
  patterns Rogo reviewers most often flag (tenant scoping, error handling, reuse,
  naming, transactions, scope discipline) that lint doesn't catch. Full rulebook:
  vault note "What Rogo reviewers actually flag".

## Talking to me

- Plain, direct language. No filler, no inflated spiels.
- No em dashes. Use commas, parentheses, or colons.
- Never estimate in days. Use hours, or just describe the scope. Models ship in hours.
- Default to interactive HTML to explain a concept or walk through a design,
  not walls of text. Force understanding before proceeding.
- Never post, comment, reply, or resolve on anything human-facing (PRs, Graphite,
  Notion, Slack to people). Draft the text for me to send. Bot comments (Bugbot,
  etc.) are fine to handle directly.

## Shell environment

- zsh with: mise (runtimes), starship, atuin, zoxide (`cd` is zoxide), fzf,
  eza/bat/delta, llm. `cheat` prints the full cheatsheet.
- Prefer `rg`/`fd` over `grep`/`find`; `bat` over `cat`; `eza` over `ls`.

## Skills

- ask-rogo code: run `rogo-self-review` before finishing (also noted in Style).
- Before ANY push: the `rogo-ts-effect-reviewer` agent must PASS the diff (hard
  gate, see Workflow). It's a read-only subagent (`~/.claude/agents/`,
  `~/.codex/agents/`) reading the live ts-code-smells / rogo-self-review rulebooks.
- Before `gt submit`: `rogo-stack-review` for a pre-submit review of the stack.
- Handing work to Shrek: `delegate-to-shrek`. Watching PRs for comments: `gt-pr-watch`.
- Durable knowledge: `brain` recall before design/plan work, capture after.

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
