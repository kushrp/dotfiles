-- Snacks dashboard: the start screen doubles as a cheatsheet — it lists the
-- top keybindings so you re-learn them every time you open nvim.
return {
  {
    "folke/snacks.nvim",
    opts = {
      dashboard = {
        preset = {
          header = [[
   ███╗   ██╗██╗   ██╗██╗███╗   ███╗
   ████╗  ██║██║   ██║██║████╗ ████║
   ██╔██╗ ██║██║   ██║██║██╔████╔██║
   ██║╚██╗██║╚██╗ ██╔╝██║██║╚██╔╝██║
   ██║ ╚████║ ╚████╔╝ ██║██║ ╚═╝ ██║
   ╚═╝  ╚═══╝  ╚═══╝  ╚═╝╚═╝     ╚═╝]],
          keys = {
            { icon = " ", key = "f", desc = "Find File", action = ":lua Snacks.dashboard.pick('files')" },
            { icon = " ", key = "/", desc = "Grep Text", action = ":lua Snacks.dashboard.pick('live_grep')" },
            { icon = " ", key = "r", desc = "Recent Files", action = ":lua Snacks.dashboard.pick('oldfiles')" },
            { icon = " ", key = "s", desc = "Restore Session", section = "session" },
            { icon = " ", key = "k", desc = "Keymaps (which-key)", action = ":lua require('which-key').show({ global = true })" },
            { icon = " ", key = "?", desc = "Cheatsheet", action = ":edit " .. vim.fn.stdpath("config") .. "/CHEATSHEET.md" },
            { icon = "󰭹 ", key = "a", desc = "AI: Avante Ask", action = ":AvanteAsk" },
            { icon = "󰚩 ", key = "A", desc = "Claude Code", action = ":ClaudeCode" },
            { icon = "󰒲 ", key = "l", desc = "Lazy", action = ":Lazy" },
            { icon = " ", key = "q", desc = "Quit", action = ":qa" },
          },
        },
        sections = {
          { section = "header" },
          { section = "keys", gap = 1, padding = 1 },
          { section = "startup" },
        },
      },
    },
  },
}
