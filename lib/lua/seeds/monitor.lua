local obj = {}

local HOME = os.getenv("HOME")
local log_path = HOME .. "/private/logs/monitor/"
local interval = 60

function writeToLog(text)
    local output
    if obj._prevLogEntry == text then
        output = "<NOCHANGE>\n\n"
        print("TRUE", output)
    else
        output = text
        obj._prevLogEntry = text
    end
    output = "now: " .. os.date("%Y_%m_%d__%H:%M:%S") .. "\n" .. output
    local log_file = log_path .. "/" .. os.date("%Y_%m_%d") .. ".log"
    io.open(log_file, "a"):write(output):close()
end

function createEntry(window, allwindows)
    if window:application():title() == "loginwindow" then
        return ""
    end
    local text = ""
    text = text .. "focused window, app: " .. window:application():title() .. "; title: " .. window:title().. "\n"
    text = text .. "visible windows:\n" .. table.concat(hs.fnutils.map(allwindows, function(w)
        return "    app: " .. w:application():title() .. "; title: " .. w:title() .. "\n"
    end))
    text = text .. "\n"
    return text
end

function obj:start(config)
    writeToLog(createEntry(hs.window.focusedWindow(), hs.window.visibleWindows()))
    obj._loop = hs.timer.doEvery(interval, function()
        writeToLog(createEntry(hs.window.focusedWindow(), hs.window.visibleWindows()))
    end)
    return self
end

function obj:stop()
    obj._loop:stop()
    return self
end

return obj
