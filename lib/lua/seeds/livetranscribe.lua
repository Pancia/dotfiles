-- Live Transcribe menu bar button: one click does what Alt+Space does.
--
-- Exists so a session can be started with no keyboard at all. It runs the same
-- launcher Karabiner does, which matters: bin/live-transcribe-launch goes through
-- `open`, so LiveTranscribe.app is its own responsible process and holds the mic
-- grant. Starting the engine any other way loses that, along with the panel and
-- the copy-to-clipboard on stop.
--
-- The app's own status item only exists during a session (app life == session
-- life), so it can't serve as the way to start one. This one is always there.

local menubarRegistry = require("lib/menubarRegistry")

local obj = {}

obj._logger = hs.logger.new("livetranscribe", "info")

local NAME = "livetranscribe"
local LAUNCHER = os.getenv("HOME") .. "/dotfiles/bin/live-transcribe-launch"
local APP_BUNDLE_ID = "org.pancia.live-transcribe-app"
local POLL_SECONDS = 2

-- macOS reads a status item's position from this default, in points from the right
-- edge of the screen, so 0 asks for the rightmost slot it will allow. That slot is
-- still left of the system's own items: the clock and Control Center can't be passed.
-- Hammerspoon stores the value under both spellings. Only ever seeded when absent,
-- so a later Cmd-drag of the item sticks.
local function seedRightmostPosition()
    for _, prefix in ipairs({ "NSStatusItem", "HSNSStatusItem" }) do
        local key = prefix .. " Preferred Position " .. NAME
        if hs.settings.get(key) == nil then
            hs.settings.set(key, 0)
        end
    end
end

local function isRunning()
    return #hs.application.applicationsForBundleID(APP_BUNDLE_ID) > 0
end

function obj.refresh()
    if not obj._menubar then return end
    if isRunning() then
        obj._menubar:setTitle("🔴")
        obj._menubar:setTooltip("Live Transcribe: click to stop and copy the transcript")
    else
        obj._menubar:setTitle("🎙")
        obj._menubar:setTooltip("Live Transcribe: click to start")
    end
end

function obj.toggle()
    hs.task.new(LAUNCHER, function(exitCode, _, stderr)
        if exitCode ~= 0 then
            obj._logger.e("launcher exited " .. exitCode .. ": " .. (stderr or ""))
            hs.alert.show("Live Transcribe failed to toggle")
        end
        obj.refresh()
    end):start()
end

function obj:start()
    seedRightmostPosition()

    local mb = menubarRegistry.getOrCreate(NAME)
    obj._menubar = mb
    obj._menubar:setClickCallback(obj.toggle)

    obj.refresh()
    obj._timer = hs.timer.doEvery(POLL_SECONDS, obj.refresh)

    return obj
end

-- Soft stop: keep the menu bar object so its position survives a soft reload.
function obj:softStop()
    if obj._timer then
        obj._timer:stop()
        obj._timer = nil
    end
    obj._menubar = nil
end

function obj:stop()
    obj:softStop()
    menubarRegistry.delete(NAME)
end

return obj
