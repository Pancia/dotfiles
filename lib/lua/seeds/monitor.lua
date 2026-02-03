local obj = {}
local perfmon = require("lib/perfmon")

local HOME = os.getenv("HOME")
local log_path = HOME .. "/.local/share/monitor/"
local interval = 60
local YABAI_PATH = "/opt/homebrew/bin/yabai"

-- Activity tracking variables
local keyboardEventTypes = {hs.eventtap.event.types.keyDown}
local mouseEventTypes = {hs.eventtap.event.types.leftMouseDown, hs.eventtap.event.types.rightMouseDown, hs.eventtap.event.types.mouseMoved}

-- Window cache state (async refresh to avoid blocking eventtaps)
obj._windowCache = {}
obj._windowQueryTask = nil
obj._useYabai = hs.fs.attributes(YABAI_PATH) ~= nil

-- Async query using yabai (follows calendar seed pattern)
function obj:queryWindowsAsync()
    if self._windowQueryTask then return end  -- Already in progress

    self._windowQueryTask = hs.task.new(
        YABAI_PATH,
        function(exitCode, stdout, stderr)
            self._windowQueryTask = nil
            if exitCode == 0 then
                local ok, windows = pcall(hs.json.decode, stdout)
                if ok and windows then
                    -- Transform yabai format to hs.window-like objects
                    self._windowCache = hs.fnutils.map(windows, function(w)
                        return {
                            title = function() return w.title or "" end,
                            application = function()
                                return { title = function() return w.app or "" end }
                            end,
                            id = w.id
                        }
                    end)
                end
            end
        end,
        {"-m", "query", "--windows"}
    )
    self._windowQueryTask:start()
end

function writeToLog(entry)
    perfmon.track("monitor.writeToLog", function()
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
        local wApp = w:application()
        if wApp == nil then
            return "<no app> => " .. w:title()
        end
        return wApp:title() .. " => " .. w:title()
    end)
    entry["active"] = obj._wasActive
    return entry
end

function executeWriteLogEntry()
    perfmon.track("monitor.executeWriteLogEntry", function()
        local success, error = pcall(function()
            local focusedWindow = perfmon.track("monitor.focusedWindow", function()
                return hs.window.focusedWindow()
            end)

            -- Use cached windows (non-blocking) and trigger async refresh
            local visibleWindows
            if obj._useYabai then
                visibleWindows = obj._windowCache  -- Returns immediately
                obj:queryWindowsAsync()            -- Refresh in background
            else
                -- Fallback: skip visible windows if yabai unavailable
                visibleWindows = {}
            end

            local entry = perfmon.track("monitor.createEntry", function()
                return createEntry(focusedWindow, visibleWindows)
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

    -- Initialize window cache
    obj._windowCache = {}
    if obj._useYabai then
        obj:queryWindowsAsync()  -- Prime the cache
    end

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

    -- Cancel any pending async window query
    if obj._windowQueryTask then
        obj._windowQueryTask:terminate()
        obj._windowQueryTask = nil
    end

    return self
end

return obj
