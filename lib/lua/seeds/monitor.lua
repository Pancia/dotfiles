local obj = {}

local HOME = os.getenv("HOME")

local log_path = HOME .. "/private/logs/monitor/"

local interval = 60

function writeToLog(text)
    local log_file = log_path .. "/" .. os.date("%Y_%m_%d") .. ".log"
    io.open(log_file, "a"):write(text):close()
end

function createEntry(window, allwindows)
    local text = ""
    text = text .. "now: " .. os.date("%Y_%m_%d__%H:%M:%S") .. "\n"
    text = text .. "focused window: " .. window:application():title() .. "; title: " .. window:title().. "\n"
    text = text .. "visible windows:\n" .. table.concat(hs.fnutils.map(allwindows, function(w)
        return "    app: " .. w:application():title() .. "; title: " .. w:title() .. "\n"
    end))
    text = text .. "\n"
    return text
end

function obj:start(config)
    obj._loop = hs.timer.doEvery(interval, function()
        local log_entry = createEntry(hs.window.focusedWindow(), hs.window.visibleWindows())
        writeToLog(log_entry)
    end)
    return self
end

function obj:stop()
    obj._loop:stop()
    return self
end

return obj
