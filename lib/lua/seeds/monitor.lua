local obj = {}

local HOME = os.getenv("HOME")
local log_path = HOME .. "/private/logs/monitor/"
local interval = 60

-- Activity tracking variables
local keyboardEventTypes = {hs.eventtap.event.types.keyDown}
local mouseEventTypes = {hs.eventtap.event.types.leftMouseDown, hs.eventtap.event.types.rightMouseDown, hs.eventtap.event.types.mouseMoved}

function writeToLog(entry)
    local jsonEntry = {
        timestamp = os.date("%Y_%m_%d__%H:%M:%S"),
        focused = entry["focused"],
        visible = entry["visible"],
        active = entry["active"]
    }

    -- Check if this is a "no change" entry
    if obj._prevLogEntry ~= nil and
       obj._prevLogEntry["focused"] == entry["focused"] and
       obj._prevLogEntry["visible"] == entry["visible"] then
       jsonEntry.noChange = true
    else
        obj._prevLogEntry = entry
    end

    -- Convert to JSON string
    local jsonString = hs.json.encode(jsonEntry)

    -- Reset activity flag after logging
    obj._wasActive = false
    local log_file = log_path.."/"..os.date("%Y_%m_%d")..".log.json"

    -- Check if file has content to determine if we need a leading comma
    local file = io.open(log_file, "r")
    local needsComma = false
    if file then
        local content = file:read("*a")
        needsComma = content and #content > 0
        file:close()
    end

    local output = ""
    if needsComma then
        output = ",\n" .. jsonString
    else
        output = jsonString
    end

    io.open(log_file, "a"):write(output):close()
end

function createEntry(window, visibleWindows)
    local app = window and window:application()

    if window == nil then
        return {["focused"] = "<ERROR: window is nil>", ["active"] = obj._wasActive, ["error"] = "Window object is nil"}
    end

    if app == nil then
        return {["focused"] = "<ERROR: app is nil>", ["active"] = obj._wasActive, ["error"] = "Application object is nil"}
    end

    if app:title() == "loginwindow" or app:title() == "ScreenSaverEngine" then
        return {["focused"] = "<SLEEPING>", ["active"] = obj._wasActive}
    end
    realWindows = hs.fnutils.filter(visibleWindows, function (x)
        return x:title() ~= "" and x ~= window
    end)
    local entry = {}

    -- Handle case where app becomes nil between the check and here
    if app == nil then
        entry["focused"] = "<ERROR: app is nil>"
        entry["error"] = "Application object became nil"
    else
        entry["focused"] = app:title() .. " => " .. window:title()
    end

    entry["visible"] = hs.fnutils.map(realWindows, function(w)
        return w:application():title() .. " => " .. w:title()
    end)
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
