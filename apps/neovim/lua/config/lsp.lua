local M = {}

M.capabilities = vim.lsp.protocol.make_client_capabilities()

M.on_attach = function(client, bufnr)
  local map = function(lhs, rhs, desc)
    vim.keymap.set("n", lhs, rhs, {
      buffer = bufnr,
      desc = desc,
    })
  end

  map("gd", vim.lsp.buf.definition, "LSP definition")
  map("gD", vim.lsp.buf.declaration, "LSP declaration")
  map("gr", vim.lsp.buf.references, "LSP references")
  map("gi", vim.lsp.buf.implementation, "LSP implementation")
  map("K", vim.lsp.buf.hover, "LSP hover")
  map("<leader>cr", vim.lsp.buf.rename, "LSP rename")
  map("<leader>ca", vim.lsp.buf.code_action, "LSP code action")

  vim.bo[bufnr].omnifunc = "v:lua.vim.lsp.omnifunc"

  if vim.lsp.completion and vim.lsp.completion.enable then
    pcall(vim.lsp.completion.enable, true, client.id, bufnr, {
      autotrigger = true,
    })
  end
end

return M
