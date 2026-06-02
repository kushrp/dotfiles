-- User keymaps. LazyVim ships a thorough default set (browse via `<space>`,
-- which triggers which-key). Only add things that DON'T collide with LazyVim's
-- groups. Removed earlier: <leader>w (window group), <leader>q (quit/session
-- group), <leader>bd (LazyVim's Snacks.bufdelete is better), <leader>y
-- (redundant — clipboard=unnamedplus already yanks to the system clipboard).
-- Save is <C-s> (LazyVim default); quit is <leader>qq.

local map = vim.keymap.set

-- Open the written cheatsheet. <leader>uc ("ui: cheatsheet") so <leader>?
-- stays free for which-key's live "show all keymaps" panel.
map("n", "<leader>uc", function()
  vim.cmd("edit " .. vim.fn.stdpath("config") .. "/CHEATSHEET.md")
end, { desc = "Open cheatsheet (file)" })

-- Move highlighted lines up/down with J/K.
map("v", "J", ":m '>+1<CR>gv=gv", { desc = "Move line down" })
map("v", "K", ":m '<-2<CR>gv=gv", { desc = "Move line up" })

-- Keep cursor centered on big jumps and search results.
map("n", "<C-d>", "<C-d>zz")
map("n", "<C-u>", "<C-u>zz")
map("n", "n", "nzzzv")
map("n", "N", "Nzzzv")

-- Paste over a selection without yanking the replaced text.
map("x", "<leader>p", [["_dP]], { desc = "Paste without yanking" })
