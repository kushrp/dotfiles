# Month 1: Power

You're flowing. Now let's unlock the advanced patterns
that make terminal development genuinely faster than any GUI.

## Macros (repeat anything)

Record a sequence, replay it unlimited times:

1. `qa` — start recording into register `a`
2. Do your edit (move, change, delete, whatever)
3. `q` — stop recording
4. `@a` — replay once
5. `10@a` — replay 10 times

**Example:** Add `console.log()` around every variable on a line:
- `qa` → `0f=wviw"ayi` → `console.log(` → `Ctrl-r a` → `)` → `Esc` → `j` → `q`
- `20@a` — does it 20 more times

## Registers

| Register | Contents |
|----------|----------|
| `"a` - `"z` | Named (you control) |
| `"+` | System clipboard |
| `"0` | Last yank |
| `""` | Last delete/change |
| `".` | Last inserted text |

Use: `"ayy` yanks line into register `a`, `"ap` pastes from `a`.
View all: `:reg`

## Avante.nvim (AI pair programming)

| Key | Action |
|-----|--------|
| `<leader>aa` | Ask AI about code |
| `<leader>ae` | Edit with AI |
| `<leader>ar` | Refresh AI response |
| `<leader>at` | Toggle Avante panel |

**Tips:**
- Select code visually first, then `<leader>aa` to ask about selection
- Use `<leader>ae` to describe a change in natural language
- API key goes in `~/.local/dotfiles.d/secrets.zsh`

## Multi-file Search & Replace (Spectre)

`<leader>sr` opens project-wide search/replace:
- Type search pattern
- Type replacement
- Preview all changes
- Confirm per-file or all at once

## Advanced Navigation

| Key | Action |
|-----|--------|
| `C-o` | Jump back (previous location) |
| `C-i` | Jump forward |
| `gf` | Go to file under cursor |
| `<leader>ss` | Document symbols |
| `<leader>sS` | Workspace symbols |
| `]]` / `[[` | Next/prev function |

## Terminal Integration

From inside nvim:
- `<leader>gg` — lazygit (full git TUI)
- `:terminal` — embedded terminal
- `C-a |` then `C-l` — tmux split, move to it

## AST-based Editing (ast-grep)

From shell, structural search/replace that understands code:

```bash
# Find all console.log calls
ast-grep --pattern 'console.log($$$)' .

# Replace await with .then pattern
ast-grep --pattern 'await $EXPR' --rewrite '$EXPR.then(r => r)' .
```

## Workflow Mastery

By now your workflow should be:

1. `tmux` → `C-a T` to pick project session
2. `v .` to open nvim in project root
3. `<leader>ff` to jump to any file
4. Edit with text objects + LSP
5. `<leader>gg` for git operations
6. `C-a |` to split for terminal work
7. `dotfiles-tips` when you want to learn something new

You're not just using the terminal — you're *thinking* in it.
