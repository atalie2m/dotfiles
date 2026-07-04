return {
  {
    "mason-org/mason.nvim",
    opts = function(_, opts)
      local function add_package(package)
        opts.ensure_installed = opts.ensure_installed or {}
        if not vim.tbl_contains(opts.ensure_installed, package) then
          table.insert(opts.ensure_installed, package)
        end
      end

      opts.ui = vim.tbl_deep_extend("force", opts.ui or {}, {
        border = "rounded",
        icons = {
          package_installed = "*",
          package_pending = ">",
          package_uninstalled = "-",
        },
      })

      for _, package in ipairs({
        "black",
        "prettier",
        "prettierd",
        "shfmt",
        "stylua",
      }) do
        add_package(package)
      end
    end,
  },
  {
    "neovim/nvim-lspconfig",
    opts = function(_, opts)
      opts.inlay_hints = vim.tbl_deep_extend("force", opts.inlay_hints or {}, {
        enabled = true,
      })
      opts.codelens = vim.tbl_deep_extend("force", opts.codelens or {}, {
        enabled = true,
      })
      opts.diagnostics = vim.tbl_deep_extend("force", opts.diagnostics or {}, {
        virtual_text = false,
        virtual_lines = false,
        underline = true,
        update_in_insert = false,
        severity_sort = true,
      })

      opts.servers = opts.servers or {}
      local function use_system_lsp(server)
        opts.servers[server] = vim.tbl_deep_extend("force", opts.servers[server] or {}, {
          mason = false,
        })
      end

      for _, server in ipairs({
        "jsonls",
        "lua_ls",
        "marksman",
        "pyright",
        "ruff",
        "vtsls",
        "yamlls",
      }) do
        use_system_lsp(server)
      end

      opts.servers["*"] = opts.servers["*"] or {}
      opts.servers["*"].keys = vim.list_extend(opts.servers["*"].keys or {}, {
        { "K", vim.lsp.buf.hover, desc = "Hover" },
        { "gd", vim.lsp.buf.definition, desc = "Goto Definition" },
        { "gr", vim.lsp.buf.references, desc = "References", nowait = true },
        { "gI", vim.lsp.buf.implementation, desc = "Goto Implementation" },
        { "gy", vim.lsp.buf.type_definition, desc = "Goto Type Definition" },
        { "<leader>ca", vim.lsp.buf.code_action, desc = "Code Action", mode = { "n", "x" }, has = "codeAction" },
      })

      opts.servers.nixd = vim.tbl_deep_extend("force", opts.servers.nixd or {}, {
        mason = false,
      })
      opts.servers.lua_ls = vim.tbl_deep_extend("force", opts.servers.lua_ls or {}, {
        settings = {
          Lua = {
            hint = {
              enable = true,
              paramName = "Disable",
              arrayIndex = "Disable",
            },
            workspace = {
              checkThirdParty = false,
            },
            completion = {
              callSnippet = "Replace",
            },
          },
        },
      })
      opts.servers.vtsls = vim.tbl_deep_extend("force", opts.servers.vtsls or {}, {
        settings = {
          typescript = {
            inlayHints = {
              parameterNames = { enabled = "literals" },
              variableTypes = { enabled = false },
              propertyDeclarationTypes = { enabled = true },
              functionLikeReturnTypes = { enabled = true },
            },
          },
        },
      })
    end,
  },
  {
    "mrcjkb/rustaceanvim",
    optional = true,
    opts = function(_, opts)
      opts.server = opts.server or {}
      opts.server.default_settings = opts.server.default_settings or {}
      opts.server.default_settings["rust-analyzer"] =
        vim.tbl_deep_extend("force", opts.server.default_settings["rust-analyzer"] or {}, {
          cargo = {
            allFeatures = true,
          },
          check = {
            command = "clippy",
          },
        })
    end,
  },
}
