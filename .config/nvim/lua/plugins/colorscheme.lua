-- Lock the colorscheme to tokyonight so it matches Ghostty + zsh syntax.

return {
  {
    "folke/tokyonight.nvim",
    lazy = false,
    priority = 1000,
    opts = {
      style = "night",          -- "storm" | "moon" | "night" | "day"
      transparent = false,
      terminal_colors = true,
      styles = {
        comments = { italic = true },
        keywords = { italic = false },
        functions = {},
        variables = {},
        sidebars = "dark",
        floats = "dark",
      },
      on_highlights = function(hl, c)
        -- Make the cursorline bg slightly more visible against the bg.
        hl.CursorLine = { bg = "#1f2335" }
        hl.LineNr = { fg = c.fg_gutter }
        hl.CursorLineNr = { fg = c.orange, bold = true }
      end,
    },
  },
  {
    "LazyVim/LazyVim",
    opts = { colorscheme = "tokyonight" },
  },
}
