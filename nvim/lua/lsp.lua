function exe(command, arguments)
    local bufnr = vim.api.nvim_get_current_buf()
    local params = {
        command = command,
        arguments = arguments,
    }
    -- vim.lsp.buf_request_sync(bufnr, "workspace/executeCommand", params, 500)
    vim.lsp.buf.execute_command(params)
end

return {
    ["exe"] = exe
}
