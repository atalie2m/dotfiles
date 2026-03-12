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

        if vim.lsp.config then
          vim.lsp.config[server] = opts
          vim.lsp.enable(server)
        else
          require("lspconfig")[server].setup(opts)
        end
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
