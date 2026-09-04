# Hook scripts moved

Claude Code hook scripts live in `~/.agents/claude-hooks`
(repo `Rogo-Technologies/kush-rogo-skills`). That is the only copy.

`setup_agents()` in `install.sh` runs before `setup_claude()`. It links every
script from `~/.agents/claude-hooks` into `~/.claude/hooks`, then
`wire-hooks.py` registers the two gates in `settings.json`. By the time
`wire-settings.py` and `wire-handoff.py` name a hook path, the script is on disk.

This directory holds no hook bodies. A second copy here is what let
`require-smell-review-before-push.sh` drift back to dotfiles in September.
Add and edit hooks under `~/.agents/claude-hooks`.
