--<[.hammerspoon/init.lua]>

package.path = "/Users/" .. os.getenv("USER") .. "/dotfiles/lib/fennel/?.lua;" .. package.path
require("init")
