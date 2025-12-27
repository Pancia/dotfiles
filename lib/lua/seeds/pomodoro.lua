-- Pomodoro menubar seed
-- Shows current session type (work/break), label, and time remaining
-- Updated via hooks from pymodoro calling hs -c commands

local safeLogger = require("lib/safeLogger")
local menubarRegistry = require("lib/menubarRegistry")

local obj = {}
obj._name = "pomodoro"
obj._logger = safeLogger.new("pomodoro", "info")

-- State
obj._menubar = nil
obj._timer = nil
obj._state = {
    active = false,
    sessionType = nil,  -- "work" or "break"
    label = nil,
    endTime = nil,      -- Unix timestamp when session ends
    duration = nil,     -- Duration in minutes
}

-- Icons
local ICONS = {
    work = "🍅",
    break_short = "☕",
    break_long = "🌴",
    idle = "⏸",
}

function obj.formatTime(seconds)
    if seconds < 0 then seconds = 0 end
    local mins = math.floor(seconds / 60)
    local secs = seconds % 60
    return string.format("%d:%02d", mins, secs)
end

function obj.updateMenuTitle()
    if not obj._menubar then return end

    local title
    if not obj._state.active then
        title = ICONS.idle
    else
        local remaining = 0
        if obj._state.endTime then
            remaining = math.floor(obj._state.endTime - os.time())
        end

        local icon = ICONS.work
        if obj._state.sessionType == "break" then
            icon = ICONS.break_short
        end

        local labelPart = ""
        if obj._state.label and obj._state.label ~= "" then
            -- Truncate label to 12 chars
            local truncLabel = obj._state.label
            if #truncLabel > 12 then
                truncLabel = truncLabel:sub(1, 11) .. "…"
            end
            labelPart = truncLabel .. " "
        end

        title = string.format("%s %s%s", icon, labelPart, obj.formatTime(remaining))
    end

    local styledTitle = hs.styledtext.new(title, {
        font = {name = "Menlo-Regular", size = 12}
    })
    obj._menubar:setTitle(styledTitle)
end

function obj.tickTimer()
    obj.updateMenuTitle()

    -- Note: When session ends, pymodoro will call endSession() via hook
    -- We just keep updating the countdown display until then
end

-- Called from pymodoro hooks via hs -c
function obj.startWork(label, durationMinutes)
    obj._logger.i("Work session started:", label, durationMinutes, "min")
    obj._state = {
        active = true,
        sessionType = "work",
        label = label,
        endTime = os.time() + (durationMinutes * 60),
        duration = durationMinutes,
    }
    obj.updateMenuTitle()
end

function obj.startBreak(label, durationMinutes)
    obj._logger.i("Break started:", label, durationMinutes, "min")
    obj._state = {
        active = true,
        sessionType = "break",
        label = label,
        endTime = os.time() + (durationMinutes * 60),
        duration = durationMinutes,
    }
    obj.updateMenuTitle()
end

function obj.endSession()
    obj._logger.i("Session ended")
    obj._state = {
        active = false,
        sessionType = nil,
        label = nil,
        endTime = nil,
        duration = nil,
    }
    obj.updateMenuTitle()
end

function obj.appStopped()
    obj._logger.i("Pymodoro stopped")
    obj._state = {
        active = false,
        sessionType = nil,
        label = nil,
        endTime = nil,
        duration = nil,
    }
    obj.updateMenuTitle()
end

function obj:start(config)
    obj._logger.i("Starting pomodoro menubar")

    -- Get or create persistent menubar (survives soft reloads)
    local mb, isNew = menubarRegistry.getOrCreate("pomodoro")
    obj._menubar = mb

    -- Always update callback (points to new code after reload)
    obj._menubar:setClickCallback(function()
        -- Click to focus Kitty (where pymodoro runs)
        hs.application.launchOrFocus("kitty")
    end)

    -- Start timer to update countdown
    obj._timer = hs.timer.doEvery(1, obj.tickTimer)

    -- Initial state (only set if newly created)
    if isNew then
        obj.updateMenuTitle()
    end

    return obj
end

-- Soft stop: cleanup resources but preserve menubar (for soft reload)
function obj:softStop()
    obj._logger.i("Soft stopping pomodoro menubar")

    if obj._timer then
        obj._timer:stop()
        obj._timer = nil
    end

    -- NOTE: Do NOT delete menubar - it persists across soft reloads
    obj._menubar = nil
end

-- Hard stop: full cleanup including menubar (for hard reload)
function obj:stop()
    obj._logger.i("Stopping pomodoro menubar")
    obj:softStop()
    menubarRegistry.delete("pomodoro")
end

-- Export global functions for hs -c access
_G.pomodoroStartWork = obj.startWork
_G.pomodoroStartBreak = obj.startBreak
_G.pomodoroEndSession = obj.endSession
_G.pomodoroAppStopped = obj.appStopped

return obj
