local obj = {}

local HOME = os.getenv("HOME")
local log_path = HOME .. "/private/logs/monitor/"
local interval = 60

-- Activity tracking variables
local keyboardEventTypes = {hs.eventtap.event.types.keyDown}
local mouseEventTypes = {hs.eventtap.event.types.leftMouseDown, hs.eventtap.event.types.rightMouseDown, hs.eventtap.event.types.mouseMoved}

function writeToLog(entry)
    local output
    if obj._prevLogEntry ~= nil and 
       obj._prevLogEntry["focused"] == entry["focused"] and 
       obj._prevLogEntry["visible"] == entry["visible"] then
        output = "<NOCHANGE "..entry["focused"]..">"
        if entry["active"] then
            output = output .. " <ACTIVE>"
        else
            output = output .. " <INACTIVE>"
        end
        output = output .. "\n"
    else
        output = entry["focused"].."\n"..(entry["visible"] or "")
        if entry["active"] then
            output = output .. "<ACTIVE>\n"
        else
            output = output .. "<INACTIVE>\n"
        end
        obj._prevLogEntry = entry
    end
    output = "NOW: "..os.date("%Y_%m_%d__%H:%M:%S").."\n"..output.."\n\n"
    
    -- Reset activity flag after logging
    obj._wasActive = false
    local log_file = log_path.."/"..os.date("%Y_%m_%d")..".log"
    io.open(log_file, "a"):write(output):close()
end

function createEntry(window, visibleWindows)
    if window == nil or window:application():title() == "loginwindow" or window:application():title() == "ScreenSaverEngine" then
        return {["focused"] = "<SLEEPING>", ["active"] = obj._wasActive}
    end
    realWindows = hs.fnutils.filter(visibleWindows, function (x)
        return x:title() ~= "" and x ~= window
    end)
    local entry = {}
    entry["focused"] = "FOCUSED: " .. window:application():title() .. " => " .. window:title()
    entry["visible"] = "VISIBLE:\n" .. table.concat(hs.fnutils.map(realWindows, function(w)
        return "\t- " .. w:application():title() .. " => " .. w:title() .. "\n"
    end))
    entry["active"] = obj._wasActive
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

function activityCallback()
    -- Set the activity flag when any input is detected
    obj._wasActive = true
    return false -- Let the event propagate to the system
end

function obj:start(config)
    -- Initialize activity flag
    obj._wasActive = false
    
    -- Create event taps for keyboard and mouse
    obj._keyboardWatcher = hs.eventtap.new(keyboardEventTypes, activityCallback)
    obj._mouseWatcher = hs.eventtap.new(mouseEventTypes, activityCallback)
    
    -- Start watching for activity
    obj._keyboardWatcher:start()
    obj._mouseWatcher:start()
    
    -- Start the monitoring loop
    executeWriteLogEntry()
    obj._loop = hs.timer.doEvery(interval, executeWriteLogEntry)
    
    return self
end

function obj:stop()
    -- Stop the monitoring loop
    obj._loop:stop()
    
    -- Stop activity watchers
    if obj._keyboardWatcher then
        obj._keyboardWatcher:stop()
    end
    
    if obj._mouseWatcher then
        obj._mouseWatcher:stop()
    end
    
    return self
end

return obj
