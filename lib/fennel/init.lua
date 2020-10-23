-- CONTEXT: [[~/dotfiles/wiki/HammerSpoon.wiki]]
package.path = '/usr/local/Cellar/luarocks/3.3.1/share/lua/5.3/?.lua;'..package.path
fennel = require("fennel")
local LIB = "/Users/pancia/dotfiles/lib/fennel/"
fennel.path = LIB.."/?.fnl;"..LIB.."/seeds/?.fnl;"..LIB.."/spacehammer/?.fnl;"..fennel.path
table.insert(package.loaders or package.searchers, fennel.searcher)
require("core")
