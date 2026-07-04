vim.g.mapleader = " "
vim.g.maplocalleader = "\\"
vim.g.autoformat = true
vim.g.snacks_animate = true
vim.g.lazyvim_picker = "snacks"
vim.g.lazyvim_ts_lsp = "vtsls"
vim.g.lazyvim_python_lsp = "pyright"
vim.g.lazyvim_python_ruff = "ruff"
vim.g.lazyvim_rust_diagnostics = "rust-analyzer"
vim.g.lazyvim_prettier_needs_config = false

local opt = vim.opt

opt.runtimepath:append(vim.fn.stdpath("data") .. "/site/")

opt.number = true
opt.relativenumber = true
opt.mouse = "a"
opt.clipboard = "unnamedplus"
opt.termguicolors = true
opt.cursorline = true
opt.confirm = true
opt.breakindent = true
opt.undofile = true
opt.expandtab = true
opt.shiftwidth = 2
opt.tabstop = 2
opt.softtabstop = 2
opt.smartindent = true
opt.ignorecase = true
opt.smartcase = true
opt.hlsearch = true
opt.incsearch = true
opt.signcolumn = "yes"
opt.updatetime = 250
opt.timeoutlen = 300
opt.splitright = true
opt.splitbelow = true
opt.wrap = false
opt.list = true
opt.listchars = {
  tab = ">-",
  trail = ".",
  nbsp = "+",
}
opt.inccommand = "split"
opt.scrolloff = 8
opt.sidescrolloff = 8
opt.completeopt = "menu,menuone,noselect"
