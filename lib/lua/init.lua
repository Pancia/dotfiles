-- CONTEXT: [[~/dotfiles/wiki/HammerSpoon.wiki]]
package.path = '/opt/homebrew/Cellar/luarocks/3.9.2/share/lua/5.4/?.lua;'..package.path
fennel = require("fennel")

local LUA_LIB = "/Users/" .. os.getenv("USER") .. "/dotfiles/lib/lua/"
package.path = LUA_LIB.."/lib/?.lua;"..LUA_LIB.."/seeds/?.lua;"..package.path

dbg = require("lib/dbg")
require("hs.ipc")
hs.ipc.cliInstall("/Users/"..os.getenv("USER").."/Developer/")

require("core")
