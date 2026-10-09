-- OpenFront Spam
-- Hold a number key, then press the left mouse button: repeats "<n> <n> click" at the
-- cursor until either one is released. Move the mouse while holding to sweep it.
--
-- Paced like a hand, not a metronome: every press is held, every step is followed by a
-- gap, and each of those is drawn fresh from a normal distribution fitted to a Karabiner
-- recording of doing it manually (~375ms per cycle). `pace` scales all of it.
-- "blast" mode is the opposite: all six events at once, every `blastInterval`.
--
-- Why Hammerspoon and not Karabiner: Karabiner can remap a press, but it cannot run a
-- loop for as long as a chord is held. An eventtap plus a timer can.
--
-- Only acts while the focused window's title contains `titlePattern` (the browser tab
-- title), so number keys and clicks everywhere else are untouched even when it's on.
--
-- Not engaged from hammerspoon.lua, same as seeds.scrollblock. Lazily required over IPC:
--     hs -c 'require("seeds.openfront").toggle()'            -- your pace
--     hs -c 'require("seeds.openfront").toggle("blast")'     -- full blast
--     hs -c 'require("seeds.openfront").setPace(0.8)'    -- 0.8 = 20% faster than by hand
--     hs -c 'require("seeds.openfront").simulate(500)'   -- what the timing works out to
-- A full Hammerspoon reload resets it to OFF.
local obj = {}

-- {mean, sd, min, max} in ms, from the recording. Gaps are press-to-next-press.
obj.timing = {
    keyGap    = {130, 20, 90, 165},  -- 1 -> 1
    clickGap  = {120, 23, 85, 165},  -- 1 -> click
    loopGap   = {125, 25, 90, 200},  -- click -> next 1
    keyHold   = {60, 20, 15, 105},
    clickHold = {90, 15, 60, 105},
}
obj.pace = 1.0                 -- multiplies every delay; < 1 is faster
obj.mode = "human"             -- or "blast"
obj.blastInterval = 0.06       -- seconds per cycle in blast mode
obj.titlePattern = "openfront" -- plain, case-insensitive substring of the window title

obj._tap = nil
obj._menubar = nil
obj._timer = nil        -- the one pending step; the loop is a chain of these
obj._running = false
obj._held = nil         -- synthetic press not yet released: {code=} or {pos=}
obj._digit = nil        -- keycode of the number key physically held
obj._eatMouseUp = false -- we swallowed the physical mouseDown, so swallow its mouseUp too

local MARK = 0x0F5A11   -- eventSourceUserData stamp, so the tap ignores what we post
local types = hs.eventtap.event.types
local props = hs.eventtap.event.properties

local DIGITS = {}
for d = 0, 9 do DIGITS[hs.keycodes.map[tostring(d)]] = true end

-- Sequence of presses, each followed by the gap before the next one.
local STEPS = {
    {press = "key",   hold = "keyHold",   gap = "keyGap"},
    {press = "key",   hold = "keyHold",   gap = "clickGap"},
    {press = "click", hold = "clickHold", gap = "loopGap"},
}

-- Seconds, normally distributed (Box-Muller) and clamped to the recorded range.
local function sample(name)
    local mean, sd, lo, hi = table.unpack(obj.timing[name])
    local z = math.sqrt(-2 * math.log(1 - math.random())) * math.cos(2 * math.pi * math.random())
    return math.min(hi, math.max(lo, mean + sd * z)) * obj.pace / 1000
end

local function inGame()
    local win = hs.window.frontmostWindow()
    local title = win and win:title()
    return title ~= nil and title:lower():find(obj.titlePattern, 1, true) ~= nil
end

local function post(ev)
    ev:setProperty(props.eventSourceUserData, MARK)
    ev:post()
end

local function postKey(code, down)
    post(hs.eventtap.event.newKeyEvent({}, code, down))
end

local function postMouse(t, pos)
    local ev = hs.eventtap.event.newMouseEvent(t, pos)
    ev:setProperty(props.mouseEventClickState, 1) -- never let rapid clicks read as double-clicks
    post(ev)
end

local function release()
    local held = obj._held
    if not held then return end
    obj._held = nil
    if held.code then postKey(held.code, false) else postMouse(types.leftMouseUp, held.pos) end
end

local function stopLoop()
    obj._running = false
    if obj._timer then obj._timer:stop(); obj._timer = nil end
    release() -- never leave a synthetic key or button down
end

local function runStep(i)
    if not (obj._running and obj._digit and inGame()) then return stopLoop() end
    if not obj._tap:isEnabled() then
        -- macOS disables a tap whose callback stalls; we'd never see the release
        obj._digit, obj._eatMouseUp = nil, false
        obj._tap:start()
        return stopLoop()
    end
    if obj.mode == "blast" then
        local key, pos = obj._digit, hs.mouse.absolutePosition()
        for _ = 1, 2 do postKey(key, true); postKey(key, false) end
        postMouse(types.leftMouseDown, pos)
        postMouse(types.leftMouseUp, pos)
        obj._timer = hs.timer.doAfter(obj.blastInterval, function() runStep(1) end)
        return
    end
    local step = STEPS[i]
    local gap = sample(step.gap)
    local hold = math.min(sample(step.hold), gap - 0.010)
    if step.press == "key" then
        obj._held = {code = obj._digit}
        postKey(obj._held.code, true)
    else
        obj._held = {pos = hs.mouse.absolutePosition()}
        postMouse(types.leftMouseDown, obj._held.pos)
    end
    obj._timer = hs.timer.doAfter(hold, function()
        release()
        obj._timer = hs.timer.doAfter(gap - hold, function() runStep(i % #STEPS + 1) end)
    end)
end

local function startLoop()
    if obj._running then return end
    obj._running = true
    runStep(1)
end

local function onEvent(ev)
    if ev:getProperty(props.eventSourceUserData) == MARK then return false end
    local t = ev:getType()

    if t == types.keyDown or t == types.keyUp then
        local code = ev:getKeyCode()
        if not DIGITS[code] then return false end
        local f = ev:getFlags()
        if f.cmd or f.ctrl or f.alt then return false end
        if t == types.keyUp then
            if code == obj._digit then obj._digit = nil; stopLoop() end
            return false
        end
        if ev:getProperty(props.keyboardEventAutorepeat) == 1 then
            -- holding the key is the trigger, not a request for key repeat
            return code == obj._digit and inGame()
        end
        obj._digit = code -- a new digit mid-spam switches the loop to it
        return false
    end

    if t == types.leftMouseDown then
        if obj._digit and inGame() then
            obj._eatMouseUp = true
            startLoop()
            return true
        end
        return false
    end

    if t == types.leftMouseDragged then return obj._eatMouseUp end

    if t == types.leftMouseUp and obj._eatMouseUp then
        obj._eatMouseUp = false
        stopLoop()
        return true
    end
    return false
end

local function cycleMs()
    if obj.mode == "blast" then return math.floor(obj.blastInterval * 1000 + 0.5) end
    local m = 0
    for _, step in ipairs(STEPS) do m = m + obj.timing[step.gap][1] end
    return math.floor(m * obj.pace + 0.5)
end

local function modeLabel()
    return obj.mode == "blast" and "full blast" or "your pace"
end

local function showIndicator()
    if not obj._menubar then obj._menubar = hs.menubar.new() end
    if not obj._menubar then return end
    obj._menubar:setTitle(obj.mode == "blast" and "⚔️🔥" or "⚔️")
    obj._menubar:setTooltip("OpenFront spam is armed — click to turn off")
    obj._menubar:setClickCallback(function() obj.off() end)
end

local function hideIndicator()
    if obj._menubar then
        obj._menubar:delete()
        obj._menubar = nil
    end
end

function obj.isOn()
    return obj._tap ~= nil and obj._tap:isEnabled()
end

function obj.on(mode)
    obj.mode = mode or obj.mode
    if not obj._tap then
        obj._tap = hs.eventtap.new({
            types.keyDown, types.keyUp,
            types.leftMouseDown, types.leftMouseUp, types.leftMouseDragged,
        }, onEvent)
    end
    obj._digit, obj._eatMouseUp = nil, false
    obj._tap:start()
    showIndicator()
    hs.alert.show(string.format("⚔️ OpenFront spam armed — %s (~%dms/cycle)", modeLabel(), cycleMs()), 1.2)
    return "on"
end

function obj.off()
    stopLoop()
    if obj._tap then obj._tap:stop() end
    obj._digit, obj._eatMouseUp = nil, false
    hideIndicator()
    hs.alert.show("⚔️ OpenFront spam off", 1.2)
    return "off"
end

-- Same mode again turns it off; the other mode switches to it.
function obj.toggle(mode)
    mode = mode or "human"
    if obj.isOn() and obj.mode == mode then return obj.off() end
    return obj.on(mode)
end

function obj.setPace(pace)
    obj.pace = pace
    return string.format("pace %.2f, ~%dms per cycle", pace, cycleMs())
end

function obj.status()
    return string.format("%s, %s, ~%dms per cycle", obj.isOn() and "on" or "off",
        modeLabel(), cycleMs())
end

-- Draw n cycles from the timing model without posting anything.
function obj.simulate(n)
    n = n or 500
    local cycles, holds = {}, {}
    for _ = 1, n do
        local c = 0
        for _, step in ipairs(STEPS) do
            local gap = sample(step.gap)
            holds[#holds + 1] = math.min(sample(step.hold), gap - 0.010) * 1000
            c = c + gap * 1000
        end
        cycles[#cycles + 1] = c
    end
    local function summary(xs)
        table.sort(xs)
        local sum = 0
        for _, x in ipairs(xs) do sum = sum + x end
        return string.format("mean %.0f, min %.0f, max %.0f", sum / #xs, xs[1], xs[#xs])
    end
    return string.format("cycle ms: %s | hold ms: %s", summary(cycles), summary(holds))
end

-- Seed interface, in case it is ever engaged from hammerspoon.lua.
function obj:start(_config) return self end
function obj:stop()
    stopLoop()
    if obj._tap then obj._tap:stop(); obj._tap = nil end
    hideIndicator()
end

return obj
