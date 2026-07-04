return {
  {
    "yetone/avante.nvim",
    -- Keep updates on the known-good locked commit until upstream publishes
    -- the native darwin-aarch64-luajit artifact for the newer release tag.
    pin = true,
    opts = {
      provider = "claude",
      auto_suggestions_provider = nil,
      behaviour = {
        auto_suggestions = false,
        auto_set_highlight_group = true,
        auto_set_keymaps = true,
      },
      windows = {
        width = 35,
      },
    },
  },
}
