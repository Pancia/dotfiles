-- CONTEXT: [[~/dotfiles/wiki/HammerSpoon.wiki]]
package.path = '/opt/homebrew/Cellar/luarocks/3.7.0/share/lua/5.4/?.lua;'..package.path
fennel = require("fennel")

local LUA_LIB = "/Users/" .. os.getenv("USER") .. "/dotfiles/lib/lua/"
package.path = LUA_LIB.."/lib/?.lua;"..LUA_LIB.."/seeds/?.lua;"..package.path

dbg = require("lib/dbg")
require("hs.ipc")
hs.ipc.cliInstall("/Users/"..os.getenv("USER").."/Developer/")

require("core")

-- SPACE HAMMER / FENNEL --

local FNL_LIB = "/Users/" .. os.getenv("USER") .. "/dotfiles/lib/fennel/"
fennel.path = FNL_LIB.."/?.fnl;"..FNL_LIB.."/spacehammer/?.fnl;"..fennel.path
table.insert(package.loaders or package.searchers, fennel.searcher)
require("spacehammer.core")
