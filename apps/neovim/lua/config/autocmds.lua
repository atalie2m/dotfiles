local augroup = vim.api.nvim_create_augroup
local autocmd = vim.api.nvim_create_autocmd

local general = augroup("dotfiles.general", { clear = true })

autocmd("TextYankPost", {
  group = general,
  desc = "Highlight yanked text",
  callback = function()
    vim.highlight.on_yank({ timeout = 150 })
  end,
})

autocmd("FileType", {
  group = general,
  pattern = {
    "help",
    "man",
    "qf",
    "checkhealth",
    "lspinfo",
    "notify",
    "startuptime",
  },
  callback = function(event)
    vim.bo[event.buf].buflisted = false
    vim.keymap.set("n", "q", "<cmd>close<CR>", {
      buffer = event.buf,
      silent = true,
      desc = "Quit Buffer",
    })
  end,
})

autocmd("FileType", {
  group = general,
  pattern = { "markdown", "text", "gitcommit" },
  callback = function()
    vim.opt_local.wrap = true
    vim.opt_local.spell = true
  end,
})

autocmd("VimResized", {
  group = general,
  callback = function()
    vim.cmd("tabdo wincmd =")
  end,
})
