# Week 1: Flow

You can survive. Now let's get efficient.
Focus: text objects, multi-file navigation, git integration.

## Text Objects (the vim superpower)

The pattern: `[action][modifier][object]`

| Command | Meaning |
|---------|---------|
| `ciw` | Change inner word |
| `ci"` | Change inside quotes |
| `ci{` | Change inside braces |
| `da(` | Delete around parentheses |
| `yap` | Yank a paragraph |
| `vi[` | Visually select inside brackets |

**Actions:** `c` (change), `d` (delete), `y` (yank/copy), `v` (visual select)
**Modifiers:** `i` (inner/inside), `a` (around/including)
**Objects:** `w` (word), `"` `'` `` ` `` (quotes), `{` `(` `[` (brackets), `p` (paragraph), `t` (tag)

## Telescope (fuzzy everything)

| Key | Action |
|-----|--------|
| `<leader>ff` | Find files |
| `<leader>fg` | Live grep |
| `<leader>fb` | Find buffers |
| `<leader>fh` | Help tags |
| `<leader>fr` | Recent files |
| `<leader>fs` | Document symbols |

Inside Telescope:
- `Ctrl-j/k` — navigate results
- `Ctrl-v` — open in vertical split
- `Ctrl-x` — open in horizontal split
- `Esc` — close

## Buffer Management

| Key | Action |
|-----|--------|
| `<leader>bb` | Switch buffer (telescope) |
| `[b` / `]b` | Previous/next buffer |
| `<leader>bd` | Delete buffer |

## Git Workflow (lazygit)

Press `<leader>gg` from nvim or `lg` from shell.

| Key | Action |
|-----|--------|
| `space` | Stage/unstage |
| `c` | Commit |
| `P` | Push |
| `p` | Pull |
| `tab` | Switch panels |
| `[` / `]` | Scroll through commits |
| `enter` | View diff |

## LSP (Language Server)

| Key | Action |
|-----|--------|
| `gd` | Go to definition |
| `gr` | References |
| `K` | Hover docs |
| `<leader>ca` | Code actions |
| `<leader>rn` | Rename |
| `]d` / `[d` | Next/prev diagnostic |

## Practice Drill

1. Open a code file: `<leader>ff`
2. Find a function name: `/functionName`
3. Go to its definition: `gd`
4. Change the function name: `ciw` → type new name → `Esc`
5. Find all references: `gr`
6. Open lazygit: `<leader>gg`
7. Stage the change: `space`
8. Commit: `c` → type message → confirm
