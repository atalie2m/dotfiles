return {
  {
    "mason-org/mason.nvim",
    cmd = "Mason",
    opts = {
      ui = {
        border = "rounded",
        icons = {
          package_installed = "*",
          package_pending = ">",
          package_uninstalled = "-",
        },
      },
    },
  },
  {
    "neovim/nvim-lspconfig",
    event = { "BufReadPre", "BufNewFile" },
    dependencies = {
      "mason-org/mason.nvim",
    },
    config = function()
      local lsp = require("config.lsp")
      local lspconfig = require("lspconfig")

      local servers = {
        nixd = {},
        lua_ls = {
          settings = {
            Lua = {
              diagnostics = {
                globals = { "vim" },
              },
              workspace = {
                checkThirdParty = false,
              },
              completion = {
                callSnippet = "Replace",
              },
            },
          },
        },
        ts_ls = {},
        pyright = {},
      }

      for server, server_opts in pairs(servers) do
        local opts = vim.tbl_deep_extend("force", {
          capabilities = lsp.capabilities,
          on_attach = lsp.on_attach,
        }, server_opts)
        lspconfig[server].setup(opts)
      end

      vim.diagnostic.config({
        severity_sort = true,
        virtual_text = {
          source = "if_many",
        },
        float = {
          border = "rounded",
          source = "if_many",
        },
      })
    end,
  },
}
