-- Drive one Hammerspoon seed under plain lua5.4, with a stub `hs`.
--
--   lua5.4 harness.lua <seed module> <config file or -> <call> [-- <call>]...
--
-- A call is an event name followed by key=value params, e.g.
--   r v=ab121
-- The special call `__stop` runs the seed's stop(). The config file, if
-- given, is a Lua chunk returning the table passed to start().
--
-- Output, one record per line, with \ tab and newline escaped:
--   ALERT <text>     each hs.alert.show
--   PASTE <text>     each hs.pasteboard.setContents
--   BOUND <event>    each handler still bound at the end
--   ERROR <text>     a call whose handler is missing or raised

local here = arg[0]:match("^(.*)/[^/]+$") or "."
-- tests/lib/lua -> the repo's lib/lua, where `seeds.*` live.
package.path = here .. "/../../../lib/lua/?.lua;" .. package.path

local function esc(s)
    return (tostring(s):gsub("\\", "\\\\"):gsub("\t", "\\t"):gsub("\n", "\\n"))
end
local function out(kind, s) io.write(kind, "\t", esc(s), "\n") end

local binds = {}
hs = {
    alert = { show = function(msg) out("ALERT", msg) end },
    pasteboard = { setContents = function(s) out("PASTE", s) return true end },
    urlevent = { bind = function(name, fn) binds[name] = fn end },
}

local seed_name, config_file = arg[1], arg[2]
local config = {}
if config_file and config_file ~= "-" then config = assert(dofile(config_file)) end
local seed = require(seed_name)
seed:start(config)

-- Split the remaining arguments into calls at each "--".
local calls, cur = {}, nil
for i = 3, #arg do
    if arg[i] == "--" then
        cur = nil
    elseif not cur then
        cur = { event = arg[i], params = {} }
        calls[#calls + 1] = cur
    else
        local k, v = arg[i]:match("^([^=]*)=(.*)$")
        cur.params[k or arg[i]] = v or ""
    end
end

for _, c in ipairs(calls) do
    if c.event == "__stop" then
        seed:stop()
    elseif not binds[c.event] then
        out("ERROR", "no handler for " .. c.event)
    else
        local ok, err = pcall(binds[c.event], c.event, c.params)
        if not ok then out("ERROR", err) end
    end
end

local names = {}
for name in pairs(binds) do names[#names + 1] = name end
table.sort(names)
for _, name in ipairs(names) do out("BOUND", name) end
