return {
  "folke/which-key.nvim",
  event = "VeryLazy",
  opts = {
    preset = "modern",
  },
  config = function(_, opts)
    local wk = require("which-key")
    wk.setup(opts)

    wk.add({
      { "<leader>c", group = "code" },
      { "<leader>f", group = "find" },
      { "<leader>x", group = "diagnostics" },
    })
  end,
}
