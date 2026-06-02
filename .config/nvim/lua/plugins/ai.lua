-- AI plugins for Neovim. Two complementary tools:
--
--   * avante.nvim  — Cursor-like inline AI: <leader>aa to chat, <leader>ae
--     to edit selection, <leader>ar to refresh suggestion. Streams into a
--     side panel with diffs you can apply.
--
--   * claudecode.nvim — full Claude Code integration. <leader>cc launches
--     Claude in a terminal split, with file/selection context auto-attached.
--
-- Both expect API keys in ~/.extra:
--   export ANTHROPIC_API_KEY="..."
--   export OPENAI_API_KEY="..."        (optional, for avante openai provider)
--
-- GitHub Copilot is already enabled via lazyvim.plugins.extras.coding.copilot
-- in lua/config/lazy.lua, so we don't redeclare it here. Set up authentication
-- once with `:Copilot auth`.

return {
  ----------------------------------------------------------------------------
  -- avante.nvim — Cursor-like inline AI
  ----------------------------------------------------------------------------
  {
    "yetone/avante.nvim",
    event = "VeryLazy",
    version = false, -- always use latest
    opts = {
      provider = "claude",
      -- Current avante nests provider config under `providers`; top-level
      -- `claude = {}` is ignored. temperature/max_tokens go in extra_request_body.
      providers = {
        claude = {
          endpoint = "https://api.anthropic.com",
          model = "claude-sonnet-4-6",
          extra_request_body = {
            temperature = 0,
            max_tokens = 8192,
          },
        },
      },
      behaviour = {
        auto_suggestions = false, -- avoid double-suggestions with copilot
        auto_set_highlight_group = true,
        auto_set_keymaps = true,
        auto_apply_diff_after_generation = false,
        support_paste_from_clipboard = true,
      },
      mappings = {
        ask = "<leader>aa",
        edit = "<leader>ae",
        refresh = "<leader>ar",
        focus = "<leader>af",
        toggle = {
          default = "<leader>at",
          debug = "<leader>ad",
          hint = "<leader>ah",
          suggestion = "<leader>as",
          repomap = "<leader>aR",
        },
        diff = {
          ours = "co",
          theirs = "ct",
          all_theirs = "ca",
          both = "cb",
          cursor = "cc",
          next = "]x",
          prev = "[x",
        },
      },
      windows = {
        width = 40,
        wrap = true,
      },
    },
    build = "make",
    dependencies = {
      "stevearc/dressing.nvim",
      "nvim-lua/plenary.nvim",
      "MunifTanjim/nui.nvim",
      "nvim-tree/nvim-web-devicons",
      {
        "MeanderingProgrammer/render-markdown.nvim",
        opts = {
          file_types = { "markdown", "Avante" },
        },
        ft = { "markdown", "Avante" },
      },
    },
  },

  ----------------------------------------------------------------------------
  -- claudecode.nvim — Claude Code terminal integration
  ----------------------------------------------------------------------------
  {
    "coder/claudecode.nvim",
    dependencies = { "folke/snacks.nvim" },
    config = true,
    -- Under <leader>A (capital) so it doesn't clobber LazyVim's <leader>c code
    -- group (format/rename/action) or avante's <leader>a.
    keys = {
      { "<leader>Ac", "<cmd>ClaudeCode<cr>", desc = "Toggle Claude Code" },
      { "<leader>Af", "<cmd>ClaudeCodeFocus<cr>", desc = "Focus Claude Code" },
      { "<leader>Ar", "<cmd>ClaudeCode --resume<cr>", desc = "Resume Claude Code" },
      { "<leader>AC", "<cmd>ClaudeCode --continue<cr>", desc = "Continue Claude Code" },
      { "<leader>Ab", "<cmd>ClaudeCodeAdd %<cr>", desc = "Add current buffer" },
      { "<leader>As", "<cmd>ClaudeCodeSend<cr>", mode = "v", desc = "Send to Claude Code" },
      { "<leader>Aa", "<cmd>ClaudeCodeDiffAccept<cr>", desc = "Accept Claude diff" },
      { "<leader>Ad", "<cmd>ClaudeCodeDiffDeny<cr>", desc = "Deny Claude diff" },
    },
  },

  ----------------------------------------------------------------------------
  -- which-key group labels for the AI prefixes
  ----------------------------------------------------------------------------
  {
    "folke/which-key.nvim",
    opts = function(_, opts)
      opts.spec = opts.spec or {}
      table.insert(opts.spec, { "<leader>a", group = "AI (avante)" })
      table.insert(opts.spec, { "<leader>A", group = "Claude Code" })
      return opts
    end,
  },
}
