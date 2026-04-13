local obj = {}
local perfmon = require("lib/perfmon")

local HOME = os.getenv("HOME")
local log_path = HOME .. "/.local/share/monitor/"
local interval = 20

-- Activity tracking variables
local keyboardEventTypes = {hs.eventtap.event.types.keyDown}
local mouseEventTypes = {hs.eventtap.event.types.leftMouseDown, hs.eventtap.event.types.rightMouseDown, hs.eventtap.event.types.mouseMoved}

function writeToLog(entry)
    perfmon.track("monitor.writeToLog", function()
        local jsonEntry = {
            timestamp = os.date("%Y_%m_%d__%H:%M:%S"),
            focused = entry["focused"],
            active = entry["active"]
        }

        -- Check if this is a "no change" entry
        if obj._prevLogEntry ~= nil and
           obj._prevLogEntry["focused"] == entry["focused"] then
           jsonEntry.noChange = true
        else
            obj._prevLogEntry = entry
        end

        -- Convert to JSON string
        local jsonString = perfmon.track("monitor.jsonEncode", function()
            return hs.json.encode(jsonEntry)
        end)

        -- Reset activity flag after logging
        obj._wasActive = false
        local log_file = log_path.."/"..os.date("%Y_%m_%d")..".log.json"

        -- Check if file has content to determine if we need a leading comma
        perfmon.track("monitor.fileRead", function()
            local file = io.open(log_file, "r")
            obj._needsComma = false
            if file then
                local content = file:read("*a")
                obj._needsComma = content and #content > 0
                file:close()
            end
        end)

        local output = ""
        if obj._needsComma then
            output = ",\n" .. jsonString
        else
            output = jsonString
        end

        perfmon.track("monitor.fileWrite", function()
            io.open(log_file, "a"):write(output):close()
        end)
    end)
end

function createEntry(window)
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

    local title = window:title()
    local privatePatterns = {"%(Private%)", "%(Incognito%)", "%(InPrivate%)", "Private Browsing"}
    for _, pattern in ipairs(privatePatterns) do
        if title:find(pattern) then
            return {["focused"] = "<PRIVATE>", ["active"] = obj._wasActive}
        end
    end

    return {
        ["focused"] = app:title() .. " => " .. title,
        ["active"] = obj._wasActive
    }
end

function executeWriteLogEntry()
    perfmon.track("monitor.executeWriteLogEntry", function()
        local success, error = pcall(function()
            local focusedWindow = perfmon.track("monitor.focusedWindow", function()
                return hs.window.focusedWindow()
            end)

            local entry = perfmon.track("monitor.createEntry", function()
                return createEntry(focusedWindow)
            end)
            writeToLog(entry)
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
    end)
end

function activityCallback(event)
    return perfmon.track("monitor.eventtap.activity", function()
        -- Set the activity flag when any input is detected
        obj._wasActive = true
        return false -- Let the event propagate to the system
    end)
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
