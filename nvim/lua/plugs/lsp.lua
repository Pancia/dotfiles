-- LSP configuration (Neovim 0.11+ native API)
local opts = { noremap=true, silent=true }
vim.keymap.set('n', ',de', vim.diagnostic.open_float, opts)
vim.keymap.set('n', ',dq', vim.diagnostic.setloclist, opts)
vim.keymap.set('n', '[d', vim.diagnostic.goto_prev, opts)
vim.keymap.set('n', ']d', vim.diagnostic.goto_next, opts)

-- LSP keymaps on attach
vim.api.nvim_create_autocmd('LspAttach', {
    callback = function(args)
        local bufnr = args.buf
        vim.keymap.set('n', 'gd', vim.lsp.buf.definition, { buffer = bufnr, silent = true })
        vim.keymap.set('n', 'K', vim.lsp.buf.hover, { buffer = bufnr, silent = true })
        vim.keymap.set('n', 'gD', vim.lsp.buf.declaration, { buffer = bufnr, silent = true })
        vim.keymap.set('n', 'gi', vim.lsp.buf.implementation, { buffer = bufnr, silent = true })
    end,
})

local capabilities = require('cmp_nvim_lsp').default_capabilities()

-- Configure and enable LSP servers
local servers = { 'clojure_lsp' }
for _, server in ipairs(servers) do
    vim.lsp.config(server, {
        capabilities = capabilities,
    })
    vim.lsp.enable(server)
end
