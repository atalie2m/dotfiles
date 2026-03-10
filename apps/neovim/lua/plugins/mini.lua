return {
  "nvim-mini/mini.nvim",
  version = false,
  event = "VeryLazy",
  config = function()
    require("mini.ai").setup()
    require("mini.operators").setup()
    require("mini.surround").setup()
  end,
}
