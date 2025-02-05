local obj = {}

local HOME = os.getenv("HOME")
local log_path = HOME .. "/private/logs/monitor/"
local interval = 60

function writeToLog(entry)
    local output
    if obj._prevLogEntry ~= nil and obj._prevLogEntry["focused"] == entry["focused"] and obj._prevLogEntry["visible"] == entry["visible"] then
        output = "<NOCHANGE "..entry["focused"]..">\n"
    else
        output = entry["focused"].."\n"..(entry["visible"] or "")
        obj._prevLogEntry = entry
    end
    output = "NOW: "..os.date("%Y_%m_%d__%H:%M:%S").."\n"..output.."\n\n"
    local log_file = log_path.."/"..os.date("%Y_%m_%d")..".log"
    io.open(log_file, "a"):write(output):close()
end

function createEntry(window, visibleWindows)
    if window == nil or window:application():title() == "loginwindow" or window:application():title() == "ScreenSaverEngine" then
        return {["focused"] = "<SLEEPING>"}
    end
    realWindows = hs.fnutils.filter(visibleWindows, function (x)
        return x:title() ~= "" and x ~= window
    end)
    local entry = {}
    entry["focused"] = "FOCUSED: " .. window:application():title() .. " => " .. window:title()
    entry["visible"] = "VISIBLE:\n" .. table.concat(hs.fnutils.map(realWindows, function(w)
        return "\t- " .. w:application():title() .. " => " .. w:title() .. "\n"
    end))
    return entry
end

function executeWriteLogEntry()
    local success, error = pcall(function()
        writeToLog(createEntry(hs.window.focusedWindow(), hs.window.visibleWindows()))
    end)
    if not success then
        print("Monitor Error executing log write:")
        print("tostring(error):" .. tostring(error))
        print("hs.inspect(error):" .. hs.inspect(error))
        hs.notify.new(nil, {
            ["title"] = "Monitor Error",
            ["withdrawAfter"] = 0
        }):send()
    end
end

function obj:start(config)
    executeWriteLogEntry()
    obj._loop = hs.timer.doEvery(interval, executeWriteLogEntry)
    return self
end

function obj:stop()
    obj._loop:stop()
    return self
end

return obj
