-- Bootstrap lazy.nvim, load LazyVim's defaults, then merge in user plugins.
-- This is the standard LazyVim starter pattern with our overrides on top.

local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  local out = vim.fn.system({
    "git", "clone", "--filter=blob:none", "--branch=stable",
    "https://github.com/folke/lazy.nvim.git", lazypath,
  })
  if vim.v.shell_error ~= 0 then
    vim.api.nvim_echo({
      { "Failed to clone lazy.nvim:\n", "ErrorMsg" },
      { out, "WarningMsg" },
      { "\nPress any key to exit." },
    }, true, {})
    vim.fn.getchar()
    os.exit(1)
  end
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup({
  spec = {
    -- LazyVim core + its default plugin suite (telescope, treesitter, mason,
    -- lsp, gitsigns, mini.pairs, which-key, lualine, ...). Browse them with
    -- `:LazyExtras` once running.
    -- `version = "*"` follows the latest semver tag (e.g. v14.x.x), so
    -- breaking changes only land when you `:Lazy update`.
    { "LazyVim/LazyVim", import = "lazyvim.plugins", version = "*" },

    -- Language extras (auto-installs LSP + treesitter for these).
    { import = "lazyvim.plugins.extras.lang.typescript" },
    { import = "lazyvim.plugins.extras.lang.json" },
    { import = "lazyvim.plugins.extras.lang.markdown" },
    { import = "lazyvim.plugins.extras.lang.python" },
    { import = "lazyvim.plugins.extras.lang.rust" },
    { import = "lazyvim.plugins.extras.lang.go" },

    -- Tooling extras.
    { import = "lazyvim.plugins.extras.ai.copilot" }, -- Copilot lives under ai.* now (was coding.copilot, which no longer exists)
    { import = "lazyvim.plugins.extras.editor.fzf" },
    { import = "lazyvim.plugins.extras.dap.core" },
    { import = "lazyvim.plugins.extras.test.core" },
    { import = "lazyvim.plugins.extras.formatting.prettier" },
    { import = "lazyvim.plugins.extras.linting.eslint" },

    -- Local overrides live in lua/plugins/*.lua and are merged automatically.
    { import = "plugins" },
  },
  defaults = {
    lazy = false,
    version = false, -- always use the latest git commit
  },
  install = { colorscheme = { "tokyonight", "habamax" } },
  checker = { enabled = true, notify = false }, -- auto-check for plugin updates
  performance = {
    rtp = {
      disabled_plugins = {
        "gzip", "tarPlugin", "tohtml", "tutor", "zipPlugin",
      },
    },
  },
})
