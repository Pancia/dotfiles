-- QuickTime: YouTube-style keys for QuickTime Player.
--   j  back 10 seconds
--   k  play / pause
--   l  forward 10 seconds
--   ,  back one frame (pauses first)
--   .  forward one frame (pauses first)
--
-- QuickTime has no setting for these, and macOS App Shortcuts only remap menu
-- items, which seeking is not. So an eventtap catches these keys and sends
-- QuickTime an AppleScript command (current time, play, pause, step).
--
-- The tap runs only while QuickTime is the front app, and passes a key through
-- when it has a modifier or a text field has focus (a Save dialog's name box).
-- The first use asks to let Hammerspoon control QuickTime Player (Automation).

local obj = {}
obj._name = "quicktime"

local config = {
    bundleID = "com.apple.QuickTimePlayerX",
    seconds = 10,
    -- Apps whose floating panels read keys while QuickTime stays in front.
    overlayApps = { "hermes" },
}

local tap = nil
local watcher = nil

local TEXT_ROLES = { AXTextField = true, AXTextArea = true, AXComboBox = true }

-- A seek takes QuickTime a moment, and a read of "current time" right after one
-- can return the old time. So quick repeated presses (a held key) build on the
-- last target we set, not on what QuickTime reports. Tested: with no gap
-- between seeks, about one in eight was lost before this.
local REPEAT_WINDOW = 0.25 -- seconds: longer would ignore time played since
local lastTarget, lastAt = nil, 0

local function seekScript(delta)
    local base = "(current time)"
    if lastTarget and hs.timer.secondsSinceEpoch() - lastAt < REPEAT_WINDOW then
        base = string.format("%.3f", lastTarget)
    end
    return string.format([[
tell application "QuickTime Player"
    if (count of documents) is 0 then return -1
    tell front document
        set t to %s + (%d)
        if t < 0 then set t to 0
        if t > duration then set t to duration
        set current time to t
        return t
    end tell
end tell]], base, delta)
end

local TOGGLE_SCRIPT = [[
tell application "QuickTime Player"
    if (count of documents) is 0 then return
    tell front document
        if playing then
            pause
        else
            play
        end if
    end tell
end tell]]

local function run(script, isSeek)
    local ok, result, err = hs.osascript.applescript(script)
    if not ok then
        print("quicktime: " .. hs.inspect(err))
        lastTarget = nil
    elseif isSeek and type(result) == "number" and result >= 0 then
        lastTarget, lastAt = result, hs.timer.secondsSinceEpoch()
    end
end

-- Like YouTube: a frame step pauses the video first.
local function stepScript(direction)
    return string.format([[
tell application "QuickTime Player"
    if (count of documents) is 0 then return
    tell front document
        if playing then pause
        step %s
    end tell
end tell]], direction)
end

-- For tests run over `hs -c`: they swap "front document" for a test file.
obj._seekScript, obj._toggleScript, obj._run = seekScript, TOGGLE_SCRIPT, run
obj._stepScript = stepScript

-- True when the player keys should reach QuickTime as typing, not as player keys:
-- a text field has focus, or another app's floating panel has the keyboard.
-- Hermes (Cmd+Space) is a panel that does not take over the front app, so
-- QuickTime stays frontmost while Hermes reads keys.
local function keysBelongElsewhere()
    local ok, elsewhere = pcall(function()
        for _, name in ipairs(config.overlayApps) do
            local app = hs.application.find(name)
            if app and #app:visibleWindows() > 0 then return true end
        end
        local sw = hs.axuielement.systemWideElement()
        local focusedApp = sw:attributeValue("AXFocusedApplication")
        local qt = hs.application.frontmostApplication()
        if focusedApp and qt and focusedApp:pid() ~= qt:pid() then return true end
        local el = sw:attributeValue("AXFocusedUIElement")
        local role = el and el:attributeValue("AXRole")
        return role ~= nil and TEXT_ROLES[role] == true
    end)
    return ok and elsewhere
end
obj._keysBelongElsewhere = keysBelongElsewhere

local function handleKey(event)
    local flags = event:getFlags()
    if flags.cmd or flags.alt or flags.ctrl or flags.shift then return false end

    local code = event:getKeyCode()
    local map = hs.keycodes.map
    local action
    if code == map.j then
        action = function() run(seekScript(-config.seconds), true) end
    elseif code == map.l then
        action = function() run(seekScript(config.seconds), true) end
    elseif code == map.k then
        action = function() lastTarget = nil; run(TOGGLE_SCRIPT) end
    elseif code == map[","] then
        action = function() lastTarget = nil; run(stepScript("backward")) end
    elseif code == map["."] then
        action = function() lastTarget = nil; run(stepScript("forward")) end
    else
        return false
    end

    if keysBelongElsewhere() then return false end
    -- A held k would flip play/pause on every repeat; the others may repeat.
    if code == map.k and event:getProperty(
            hs.eventtap.event.properties.keyboardEventAutorepeat) ~= 0 then
        return true
    end
    -- Leave the tap callback first: a slow AppleScript here would stall typing.
    -- The script is built in the timer, so a queued repeat sees the last target.
    hs.timer.doAfter(0, action)
    return true
end

local function setActive(active)
    lastTarget = nil
    if active then tap:start() else tap:stop() end
end

function obj:start(cfg)
    for k, v in pairs(cfg or {}) do config[k] = v end
    tap = hs.eventtap.new({ hs.eventtap.event.types.keyDown }, handleKey)
    watcher = hs.application.watcher.new(function(_, kind, app)
        if not app or app:bundleID() ~= config.bundleID then
            if kind == hs.application.watcher.activated then setActive(false) end
            return
        end
        if kind == hs.application.watcher.activated then
            setActive(true)
        elseif kind == hs.application.watcher.deactivated
            or kind == hs.application.watcher.terminated then
            setActive(false)
        end
    end)
    watcher:start()
    local front = hs.application.frontmostApplication()
    setActive(front ~= nil and front:bundleID() == config.bundleID)
    return self
end

function obj:stop()
    if watcher then watcher:stop(); watcher = nil end
    if tap then tap:stop(); tap = nil end
end

return obj
