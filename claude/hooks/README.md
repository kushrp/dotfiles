# Hook scripts moved

Canonical Claude Code hook scripts live in
`~/.agents/claude-hooks` (repo `Rogo-Technologies/kush-rogo-skills`).

`install.sh` still links `cc-status.sh` and the handoff trio from this
directory as a bootstrap fallback, then `setup_agents` relinks every
script from `~/.agents/claude-hooks`.

Edit the copy under `~/.agents/claude-hooks`. Do not add new hook bodies
here.
