-- User autocmds; LazyVim ships sensible defaults.

local augroup = vim.api.nvim_create_augroup
local autocmd = vim.api.nvim_create_autocmd

-- Highlight on yank.
autocmd("TextYankPost", {
  group = augroup("HighlightYank", { clear = true }),
  callback = function()
    vim.highlight.on_yank({ timeout = 200 })
  end,
})

-- Strip trailing whitespace on save (except .md where it's significant).
autocmd("BufWritePre", {
  group = augroup("StripWhitespace", { clear = true }),
  pattern = { "*" },
  callback = function(args)
    if vim.bo[args.buf].filetype == "markdown" then return end
    local save = vim.fn.winsaveview()
    vim.cmd([[%s/\s\+$//e]])
    vim.fn.winrestview(save)
  end,
})
