-- CONTEXT: [[~/dotfiles/wiki/HammerSpoon.wiki]]
local _initStart = hs.timer.absoluteTime()
_G._profile = {}

package.path = '/opt/homebrew/Cellar/luarocks/3.9.2/share/lua/5.4/?.lua;'..package.path

local _s = hs.timer.absoluteTime()
fennel = require("fennel")
table.insert(_G._profile, string.format("  fennel: %.1fms", (hs.timer.absoluteTime() - _s) / 1e6))

local LUA_LIB = "/Users/" .. os.getenv("USER") .. "/dotfiles/lib/lua/"
package.path = LUA_LIB.."/lib/?.lua;"..LUA_LIB.."/seeds/?.lua;"..package.path

_s = hs.timer.absoluteTime()
dbg = require("lib/dbg")
table.insert(_G._profile, string.format("  dbg: %.1fms", (hs.timer.absoluteTime() - _s) / 1e6))

_s = hs.timer.absoluteTime()
require("hs.ipc")
hs.ipc.cliInstall("/Users/"..os.getenv("USER").."/Developer/")
table.insert(_G._profile, string.format("  ipc: %.1fms", (hs.timer.absoluteTime() - _s) / 1e6))

require("core")

table.insert(_G._profile, string.format("init total: %.1fms", (hs.timer.absoluteTime() - _initStart) / 1e6))
hs.printf("[profile:start]\n%s", table.concat(_G._profile, "\n"))
