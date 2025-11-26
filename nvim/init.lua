local HOME = os.getenv("HOME")
package.path = HOME.."/dotfiles/nvim/lua/?.lua;" .. package.path
package.path = HOME.."/.config/nvim/plugged/conjure/lua/?.lua;" .. package.path

require('plugs/hop')
if not vim.g.vscode then
    require('plugs/lsp')
    require('plugs/cmp')
end

vim.api.nvim_create_autocmd("VimEnter", {
    callback = function()
        if vim.fn.argc() == 0 then
            -- Show your custom content
            vim.cmd("enew")
            local lines = {
                "Welcome back Commander! o7",
            }
            vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
            vim.bo.modifiable = false
            vim.bo.buftype = 'nofile'
        end
    end
})
