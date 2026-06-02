-- which-key is the always-available cheatsheet. Press <space> and the menu
-- appears immediately (delay = 0); the "helix" preset renders it as a
-- readable right-hand panel. <leader>? shows EVERY keymap.
return {
  {
    "folke/which-key.nvim",
    event = "VeryLazy",
    opts = {
      preset = "helix",
      delay = 0,
      icons = { mappings = true },
      spec = {
        { "<leader>b", group = "buffer" },
        { "<leader>c", group = "code" }, -- LazyVim's own group; don't relabel
        { "<leader>f", group = "find/file" },
        { "<leader>g", group = "git" },
        { "<leader>q", group = "quit/session" },
        { "<leader>s", group = "search" },
        { "<leader>u", group = "ui/toggle" },
        { "<leader>w", group = "window" },
        { "<leader>x", group = "diagnostics/quickfix" },
      },
    },
    keys = {
      {
        "<leader>?",
        function() require("which-key").show({ global = true }) end,
        desc = "All keymaps (which-key)",
      },
    },
  },
}
