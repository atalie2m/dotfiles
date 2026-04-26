local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
local config_lockfile = vim.fn.stdpath("config") .. "/lazy-lock.json"
local state_lockfile = vim.fn.stdpath("state") .. "/lazy-lock.json"

if not (vim.uv or vim.loop).fs_stat(lazypath) then
  local url = "https://github.com/folke/lazy.nvim.git"
  local clone_result = vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "--branch=stable",
    url,
    lazypath,
  })

  if vim.v.shell_error ~= 0 then
    error("Failed to clone lazy.nvim:\n" .. clone_result)
  end
end

vim.opt.rtp:prepend(lazypath)

local function ensure_state_lockfile()
  if vim.fn.filereadable(state_lockfile) == 1 then
    return
  end

  if vim.fn.filereadable(config_lockfile) ~= 1 then
    return
  end

  vim.fn.mkdir(vim.fn.fnamemodify(state_lockfile, ":h"), "p")
  local lines = vim.fn.readfile(config_lockfile)
  local ok, err = pcall(vim.fn.writefile, lines, state_lockfile)
  if not ok then
    vim.schedule(function()
      vim.notify("lazy.nvim: failed to seed state lockfile: " .. tostring(err), vim.log.levels.WARN)
    end)
  end
end

local config_dir_writable = vim.fn.filewritable(vim.fn.stdpath("config")) == 2
local config_lockfile_writable = vim.fn.filewritable(config_lockfile) == 1
local lockfile = config_lockfile

if not config_dir_writable or not config_lockfile_writable then
  ensure_state_lockfile()
  lockfile = state_lockfile
end

require("lazy").setup({
  spec = {
    { "LazyVim/LazyVim", import = "lazyvim.plugins" },
    { import = "lazyvim.plugins.extras.editor.snacks_picker" },
    { import = "lazyvim.plugins.extras.editor.snacks_explorer" },
    { import = "lazyvim.plugins.extras.editor.dial" },
    { import = "lazyvim.plugins.extras.editor.inc-rename" },
    { import = "lazyvim.plugins.extras.coding.yanky" },
    { import = "lazyvim.plugins.extras.coding.mini-surround" },
    { import = "lazyvim.plugins.extras.ui.edgy" },
    { import = "lazyvim.plugins.extras.formatting.prettier" },
    { import = "lazyvim.plugins.extras.lang.typescript" },
    { import = "lazyvim.plugins.extras.lang.python" },
    { import = "lazyvim.plugins.extras.lang.rust" },
    { import = "lazyvim.plugins.extras.lang.json" },
    { import = "lazyvim.plugins.extras.lang.markdown" },
    { import = "lazyvim.plugins.extras.lang.yaml" },
    { import = "lazyvim.plugins.extras.ai.avante" },
    { import = "plugins" },
  },
  defaults = {
    lazy = false,
    version = false,
  },
  lockfile = lockfile,
  checker = {
    enabled = true,
    notify = false,
  },
  change_detection = {
    notify = false,
  },
  install = {
    colorscheme = { "catppuccin", "habamax" },
  },
  performance = {
    rtp = {
      disabled_plugins = {
        "gzip",
        "matchit",
        "matchparen",
        "netrwPlugin",
        "tarPlugin",
        "tohtml",
        "tutor",
        "zipPlugin",
      },
    },
  },
})
