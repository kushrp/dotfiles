-- LazyVim loads this automatically. Use it for option overrides; for full
-- defaults, see https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua

local opt = vim.opt

opt.relativenumber = true
opt.number = true
opt.signcolumn = "yes"
opt.scrolloff = 8
opt.sidescrolloff = 8
opt.cursorline = true
opt.colorcolumn = "100"
opt.wrap = false
opt.linebreak = true

opt.tabstop = 2
opt.shiftwidth = 2
opt.expandtab = true
opt.smartindent = true

opt.ignorecase = true
opt.smartcase = true
opt.inccommand = "split"  -- live preview of :%s/// replacements

opt.undofile = true
opt.swapfile = false
opt.backup = false

opt.splitright = true
opt.splitbelow = true

opt.termguicolors = true
opt.background = "dark"

opt.clipboard = "unnamedplus"  -- use system clipboard by default
opt.mouse = "a"

-- Faster which-key popup.
vim.g.mapleader = " "
vim.g.maplocalleader = "\\"
