--<[.hammerspoon/init.lua]>

package.path = "/Users/" .. os.getenv("USER") .. "/dotfiles/lib/lua/?.lua;" .. package.path
require("init")
