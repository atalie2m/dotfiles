return {
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = "catppuccin",
    },
  },
  {
    "catppuccin/nvim",
    name = "catppuccin",
    opts = {
      flavour = "mocha",
      transparent_background = false,
      integrations = {
        native_lsp = {
          enabled = true,
        },
        snacks = true,
      },
    },
  },
}
