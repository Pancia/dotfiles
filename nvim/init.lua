local HOME = os.getenv("HOME")
package.path = HOME.."/dotfiles/nvim/lua/?.lua;" .. package.path
package.path = HOME.."/.config/nvim/plugged/conjure/lua/?.lua;" .. package.path

require('plugs/hop')
require('plugs/cmp')
require('plugs/lsp')
