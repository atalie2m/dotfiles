return {
  {
    "nvim-lualine/lualine.nvim",
    opts = function(_, opts)
      opts.options = opts.options or {}
      opts.options.globalstatus = true
      opts.options.component_separators = ""
      opts.options.section_separators = ""
    end,
  },
  {
    "folke/noice.nvim",
    opts = {
      presets = {
        bottom_search = false,
        command_palette = true,
        long_message_to_split = true,
        inc_rename = true,
      },
      lsp = {
        progress = {
          enabled = true,
        },
        hover = {
          enabled = true,
        },
        signature = {
          enabled = true,
        },
      },
    },
  },
  {
    "folke/edgy.nvim",
    opts = {
      animate = {
        enabled = false,
      },
      bottom = {
        "Trouble",
        { ft = "qf", title = "QuickFix" },
      },
      left = {
        "snacks_layout_box",
      },
    },
  },
}
