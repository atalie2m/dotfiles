return {
  "nvim-treesitter/nvim-treesitter",
  lazy = false,
  build = ":TSUpdate",
  config = function()
    local ts = require("nvim-treesitter")

    local parsers = {
      "bash",
      "javascript",
      "json",
      "lua",
      "markdown",
      "markdown_inline",
      "nix",
      "python",
      "query",
      "regex",
      "tsx",
      "typescript",
      "vim",
      "vimdoc",
      "yaml",
    }

    ts.setup({})

    local installed = ts.get_installed()
    local missing = vim.tbl_filter(function(parser)
      return not vim.list_contains(installed, parser)
    end, parsers)

    if #missing > 0 then
      ts.install(missing)
    end

    local augroup = vim.api.nvim_create_augroup("dotfiles.treesitter", { clear = true })
    vim.api.nvim_create_autocmd("FileType", {
      group = augroup,
      pattern = "*",
      callback = function(args)
        if vim.bo[args.buf].buftype ~= "" then
          return
        end

        pcall(vim.treesitter.start, args.buf)
        vim.bo[args.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
      end,
    })
  end,
}
