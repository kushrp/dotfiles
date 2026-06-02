# Neovim cheatsheet

Open this file inside Neovim with **`<space>uc`**. Forgot a binding? Press
**`<space>`** and wait — the which-key panel *is* the live cheatsheet. Or
**`<space>?`** to show every keymap, **`<space>sk`** to fuzzy-search them.

Leader = `<space>`. `g` and `<leader>` followed by any key pops a which-key menu
that shows what's bound — you don't have to memorize anything; just press the
prefix and read.

---

## Movement (no leader)

| key | does |
|---|---|
| `h j k l` | left / down / up / right |
| `w` / `b` | forward / back one word |
| `0` / `^` / `$` | line start / first nonblank / end |
| `gg` / `G` | top / bottom of file |
| `{` / `}` | prev / next paragraph |
| `Ctrl-d` / `Ctrl-u` | half-page down / up (centered) |
| `Ctrl-o` / `Ctrl-i` | jump backward / forward in jump-list |
| `%` | jump to matching bracket |
| `f<char>` / `t<char>` | jump to next `<char>` / before next `<char>` |
| `*` / `#` | search word under cursor forward / backward |
| `n` / `N` | next / prev search match (centered) |

## Edit

| key | does |
|---|---|
| `i` / `a` | insert before / after cursor |
| `I` / `A` | insert at line start / end |
| `o` / `O` | new line below / above |
| `d{motion}` | delete motion (e.g. `dw`, `d$`, `diw`, `dap`) |
| `c{motion}` | change motion (delete + insert) |
| `y{motion}` | yank (copy) |
| `p` / `P` | paste after / before |
| `u` / `Ctrl-r` | undo / redo |
| `.` | repeat last change |
| `gU{motion}` / `gu{motion}` | uppercase / lowercase |
| `>>` / `<<` | indent / outdent |
| `J` (visual) / `K` (visual) | move selection down / up (custom) |
| `<leader>p` (visual) | paste without yanking the replaced text |

## Visual mode

| key | does |
|---|---|
| `v` / `V` / `Ctrl-v` | char / line / block visual |
| `gv` | reselect last visual |
| `o` | toggle selection cursor end |

## Find / file (fzf-lua — the active picker)

| key | does |
|---|---|
| `<leader><space>` | find files (cwd) |
| `<leader>ff` | find files (cwd) |
| `<leader>fg` | live grep (rg) |
| `<leader>fb` | find open buffers |
| `<leader>fr` | recent files |
| `<leader>fh` | help tags |
| `<leader>fc` | commands |
| `<leader>sk` | search keymaps (fuzzy) |
| `<leader>/` | grep in current buffer |
| in picker: `<C-q>` → quickfix, `<C-s>` / `<C-v>` → split / vsplit |

## AI

| key | does |
|---|---|
| `<leader>aa` | Avante: ask about the buffer / selection |
| `<leader>ae` | Avante: edit selection with AI |
| `<leader>at` | Avante: toggle the side panel |
| `<leader>Ac` | Claude Code: toggle terminal |
| `<leader>Ab` | Claude Code: add current buffer as context |
| `<leader>As` | Claude Code: send selection (visual mode) |
| `<leader>Aa` / `<leader>Ad` | accept / deny a Claude diff |

## LSP (`<leader>l` and `g*`)

| key | does |
|---|---|
| `gd` | go to definition |
| `gr` | references |
| `gI` | implementation |
| `gy` | type definition |
| `K` | hover documentation |
| `<leader>ca` | code action |
| `<leader>cr` | rename symbol |
| `<leader>cf` | format buffer |
| `<leader>cd` | line diagnostics |
| `]d` / `[d` | next / prev diagnostic |
| `<leader>xx` | toggle diagnostics list |

## Git (`<leader>g`)

| key | does |
|---|---|
| `<leader>gg` | lazygit (full TUI) |
| `<leader>gb` | git blame line |
| `<leader>gB` | git browse (open file on remote) |
| `<leader>gd` | git diff hunk |
| `]h` / `[h` | next / prev hunk |
| `<leader>ghs` | stage hunk |
| `<leader>ghr` | reset hunk |
| `<leader>ghp` | preview hunk |

## Buffers / windows / tabs

| key | does |
|---|---|
| `<S-h>` / `<S-l>` | prev / next buffer |
| `<leader>bd` | delete buffer (keeps window) |
| `<leader>ww` | switch window |
| `Ctrl-w s` / `Ctrl-w v` | horizontal / vertical split |
| `Ctrl-w h/j/k/l` | move between splits |
| `Ctrl-w =` | equalize splits |
| `<leader>ws` / `<leader>wv` | LazyVim aliases for splits |

## Search / replace

| key | does |
|---|---|
| `/foo` / `?foo` | search forward / backward |
| `:%s/foo/bar/g` | replace all in buffer (live preview via `inccommand`) |
| `:noh` | clear search highlight |
| `<leader>sr` | LazyVim's search-and-replace UI |

## Terminal

| key | does |
|---|---|
| `<leader>ft` | float terminal |
| `<leader>fT` | full-window terminal |
| `<Esc><Esc>` | leave terminal mode |

## Macros / registers

| key | does |
|---|---|
| `q<letter>` then keys then `q` | record macro to `<letter>` |
| `@<letter>` | replay macro |
| `@@` | replay last macro |
| `"<letter>y` / `"<letter>p` | yank/paste to/from named register |
| `"+y` / `"+p` | system clipboard (also `<leader>y`, `<leader>p`) |
| `:reg` | list registers |

## Sessions / restore

| key | does |
|---|---|
| `<leader>qs` | restore session for cwd |
| `<leader>ql` | restore last session |

## Plugin manager

| key | does |
|---|---|
| `:Lazy` | open Lazy plugin UI |
| `:Lazy update` | update plugins |
| `:Lazy sync` | install missing + update |
| `:LazyExtras` | enable/disable LazyVim extras (langs, tools) |
| `:Mason` | manage LSPs / linters / formatters |

---

## Tips I keep forgetting

- `ciw` = change inner word. `cit` = change inner HTML tag. `ci"` = inside quotes. Same pattern for `di*` (delete), `yi*` (yank), `vi*` (select).
- `gU$` uppercase to end of line. `g~iw` toggle case of word.
- `r<char>` replace a single char. `R` enter overstrike mode.
- `Ctrl-a` / `Ctrl-x` increment / decrement number under cursor.
- `:.!cmd` replace current line with output of shell command.
- `gx` open URL under cursor.
- `K` is hover docs for LSP, but on a man-page word it opens `:Man`.
- Use `<C-w>T` to move current split into a new tab.
- `:b <partial>` jumps to a matching buffer name (tab-completable).
- `:earlier 5m` / `:later 30s` time-travels undo history.
- In telescope: `<C-q>` sends results to quickfix; `<C-x>` opens in split.

## When something feels broken

1. `:checkhealth` — vim's self-diagnosis (LSP, treesitter, providers, etc.).
2. `:Lazy log` — recent plugin errors.
3. `:LspInfo` / `:LspLog` — language server state.
4. `:Mason` — see what LSPs/linters/formatters are installed.
5. `:messages` — see notifications you missed.
