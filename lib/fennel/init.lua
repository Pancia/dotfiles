-- CONTEXT: [[~/dotfiles/wiki/HammerSpoon.wiki]]
package.path = '/opt/homebrew/Cellar/luarocks/3.7.0/share/lua/5.4/?.lua;'..package.path
fennel = require("fennel")
local LIB = "/Users/" .. os.getenv("USER") .. "/dotfiles/lib/fennel/"
fennel.path = LIB.."/?.fnl;"..LIB.."/lib/?.fnl;"..LIB.."/seeds/?.fnl;"..LIB.."/spacehammer/?.fnl;"..fennel.path
table.insert(package.loaders or package.searchers, fennel.searcher)
require("core")
dbg = require("lib/dbg")
