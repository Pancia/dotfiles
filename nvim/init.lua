local HOME = os.getenv("HOME")
package.path = HOME.."/dotfiles/nvim/lua/?.lua;" .. package.path
package.path = HOME.."/.config/nvim/plugged/conjure/lua/?.lua;" .. package.path

require('plugs/hop')
if not vim.g.vscode then
    require("chatgpt").setup()
    require('plugs/lsp')
    require('plugs/cmp')
end
