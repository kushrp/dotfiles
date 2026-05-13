# Day 1: Survive

Your goal today: open files, make edits, save, quit, and navigate between panes.
That's it. Don't try to learn everything — just these core moves.

## The Absolute Basics

| Action | Key | Memory Hook |
|--------|-----|-------------|
| Open file | `nvim filename` or `<leader>ff` | "find file" |
| Enter insert mode | `i` | "insert" |
| Exit insert mode | `Esc` | escape to safety |
| Save | `:w` | "write" |
| Quit | `:q` | "quit" |
| Save + quit | `:wq` or `ZZ` | |
| Quit without saving | `:q!` | force quit |

## Moving Around

| Action | Key |
|--------|-----|
| Left/down/up/right | `h` `j` `k` `l` |
| Start of line | `0` |
| End of line | `$` |
| Top of file | `gg` |
| Bottom of file | `G` |
| Jump to line N | `Ngg` or `:N` |

## Panes & Splits

| Action | Key |
|--------|-----|
| Split vertical | `C-a \|` (tmux) |
| Split horizontal | `C-a -` (tmux) |
| Move between panes | `C-h/j/k/l` |
| Close pane | `C-d` or `exit` |

## Finding Files

| Action | Key |
|--------|-----|
| Fuzzy find files | `<leader>ff` |
| Search in files | `<leader>fg` |
| Recent files | `<leader>fr` |
| File explorer | `<leader>e` |

## Your First Session

```bash
# 1. Start tmux
tmux

# 2. Open a project
z my-project    # or cd ~/projects/something

# 3. Open nvim
v .             # opens nvim in current dir

# 4. Try these in order:
#    <leader>ff  → type filename → Enter
#    i           → type something
#    Esc         → back to normal
#    :w          → saved!
#    C-a |       → split right
#    C-l         → move to right pane
#    C-h         → move back left
```

## Done for Today?

You survived! Tomorrow, try using `j`/`k` instead of arrow keys,
and `<leader>ff` instead of the file explorer. Muscle memory builds fast.
