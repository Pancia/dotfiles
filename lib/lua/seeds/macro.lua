-- Macro: record keyboard + mouse input against one window, then replay it in a loop.
-- Built for grinding in a game: record one pass, loop it until told to stop.
--
-- Started from Hermes (Cmd+Space -> x -> g), stopped by one hotkey:
--   record()           start recording the focused window
--   play([loops])      replay the last recording, looping until stopped (or `loops`)
--   Cmd+Ctrl+Escape    STOP: ends + saves a recording, or stops playback. Only bound
--                      while something is armed/recording/playing, so it is free otherwise.
-- Starting from Hermes works because its panel is non-activating: the game stays the
-- frontmost app and focused window. The same fact is why Hermes cannot be the *stop*
-- control — opening it trips no guard, and its own keystrokes would land in the recording.
--
-- In Shadow PC, use fn+R / fn+P / fn+1 / fn+Esc instead (a Karabiner rule in
-- rcs/karabiner.json, scoped to com.electron.shadow). Shadow forwards Cmd to the
-- remote PC as the Windows key, so Cmd+Space and Cmd+Ctrl+Esc open the Start menu
-- there. Karabiner swallows the fn combos before any app sees them and runs these same
-- functions over `hs -c`.
--
-- Guards. Recording and playback are both bound to the window that was focused when
-- they began. Either one stops the moment any of these changes:
--   * the frontmost app (application watcher, immediate; also checked before each batch)
--   * the focused window, or its position/size (polled every `guardInterval`)
--   * the current Space (spaces watcher, immediate; also polled)
-- So Cmd+Tab is a second stop key — but a recording interrupted by a guard is discarded.
--
-- Starting waits `settle` seconds (for the Hermes panel to close) and then for every
-- modifier to be released, so no launcher key or modifier ends up in a recording or
-- leaks into the game. At the end
-- of every loop and on any stop, every key and mouse button the replay left down is
-- released, so a stop can never leave W or the left button stuck.
--
-- Events are stored whole (CGEvent data), so mouse moves carry both the absolute
-- position and the raw deltas — the deltas are what a game with a captured camera reads.
-- Positions are absolute screen coordinates: playback warns if the window is not where
-- it was during recording, since clicks will land in the wrong place.
--
-- The last recording is saved to ~/.local/share/hammerspoon/macros/last.json and
-- reloaded on start. Over IPC:
--     hs -c 'return require("seeds.macro").status()'
--     hs -c 'return require("seeds.macro").save("farm-loop")'
--     hs -c 'return require("seeds.macro").load("farm-loop")'
--     hs -c 'return require("seeds.macro").list()'
local obj = {}

local T = hs.eventtap.event.types
local HOME = os.getenv("HOME")

obj.config = {
    stopHotkey = {{"cmd", "ctrl"}, "escape"},
    settle = 0.3,          -- seconds to wait after record()/play() before arming
    loops = 0,             -- 0 = loop until stopped
    loopGap = 0,           -- seconds of idle between loops
    guardInterval = 0.1,   -- seconds between window/space checks
    dir = HOME .. "/.local/share/hammerspoon/macros",
}

local CAPTURE = {
    T.keyDown, T.keyUp, T.flagsChanged,
    T.leftMouseDown, T.leftMouseUp, T.rightMouseDown, T.rightMouseUp,
    T.otherMouseDown, T.otherMouseUp,
    T.mouseMoved, T.leftMouseDragged, T.rightMouseDragged, T.otherMouseDragged,
    T.scrollWheel,
}

-- up type -> its down type, and the reverse
local DOWN_OF = {
    [T.leftMouseUp] = T.leftMouseDown,
    [T.rightMouseUp] = T.rightMouseDown,
    [T.otherMouseUp] = T.otherMouseDown,
}
local UP_OF = {}
for up, down in pairs(DOWN_OF) do UP_OF[down] = up end

local MODS = {"cmd", "alt", "shift", "ctrl", "fn"}

obj._state = "idle"      -- idle | arming | recording | playing
obj._rec = nil           -- { bundleID, appName, frame, duration (ns), events = {{t, ev}} }
obj._stopKey = nil       -- hs.hotkey, enabled only while not idle
obj._menubar = nil

local function setState(s)
    obj._state = s
    if obj._stopKey then
        if s == "idle" then obj._stopKey:disable() else obj._stopKey:enable() end
    end
end

---------------------------------------------------------------------------
-- helpers

local function now() return hs.timer.absoluteTime() end

local function alert(msg, secs) hs.alert.show(msg, secs or 1.5) end

local function setIndicator(title, tooltip)
    if not obj._menubar then
        obj._menubar = hs.menubar.new()
        if not obj._menubar then return end
        obj._menubar:setClickCallback(function() obj.halt() end)
    end
    obj._menubar:setTitle(title)
    obj._menubar:setTooltip(tooltip .. " — click to stop")
end

local function clearIndicator()
    if obj._menubar then obj._menubar:delete(); obj._menubar = nil end
end

local function anyModifierHeld()
    local m = hs.eventtap.checkKeyboardModifiers()
    for _, k in ipairs(MODS) do if m[k] then return true end end
    return false
end

-- Run fn after `settle` seconds and once no modifier is held, so the launcher's
-- keys stay out of it.
local function arm(fn)
    if obj._armTimer then obj._armTimer:stop() end
    local readyAt = now() + obj.config.settle * 1e9
    obj._armTimer = hs.timer.doEvery(0.03, function()
        if now() < readyAt or anyModifierHeld() then return end
        obj._armTimer:stop(); obj._armTimer = nil
        fn()
    end)
end

local function cancelArming()
    if obj._armTimer then obj._armTimer:stop(); obj._armTimer = nil end
end

local function frameOf(win)
    local f = win:frame()
    return {x = f.x, y = f.y, w = f.w, h = f.h}
end

local function sameFrame(a, b)
    return math.abs(a.x - b.x) < 1 and math.abs(a.y - b.y) < 1
       and math.abs(a.w - b.w) < 1 and math.abs(a.h - b.h) < 1
end

local function snapshotTarget()
    local win = hs.window.focusedWindow()
    if not win then return nil end
    local app = win:application()
    if not app then return nil end
    return {
        pid = app:pid(), bundleID = app:bundleID(), appName = app:name(),
        winID = win:id(), frame = frameOf(win), space = hs.spaces.focusedSpace(),
    }
end

-- Every recording and every playback loop starts with the cursor at the centre of the
-- target window, so input before the first recorded mouse move lands in the same place.
--
-- Repositioning the cursor is not free in a game that captures the mouse (Shadow
-- does): macOS folds the jump into the delta of the *next hardware* mouse event,
-- whoever moved the cursor (measured: an 80px move -> the next real event read
-- d=79,-1). A captured-mouse game sees that as a camera flick. So:
--   * the move itself is posted with an explicit zero delta (hs.mouse.absolutePosition
--     would carry the jump as its own delta),
--   * the jump is returned, so recording can subtract it from the first real move,
--   * during playback hardware mouse movement is swallowed (see mouseShield).
-- Returns the jump {x, y}, or nil when the cursor was already centred.
local MAGIC = 0x6d6163 -- eventSourceUserData stamped on every event this seed posts
local P = hs.eventtap.event.properties

local function centerMouse(t)
    local f = t.frame
    local c = {x = f.x + f.w / 2, y = f.y + f.h / 2}
    local cur = hs.mouse.absolutePosition()
    local jump = {x = math.floor(c.x - cur.x + 0.5), y = math.floor(c.y - cur.y + 0.5)}
    if jump.x == 0 and jump.y == 0 then return nil end
    local ev = hs.eventtap.event.newMouseEvent(T.mouseMoved, c)
    ev:setProperty(P.mouseEventDeltaX, 0)
    ev:setProperty(P.mouseEventDeltaY, 0)
    ev:setProperty(P.eventSourceUserData, MAGIC)
    ev:post()
    return jump
end

local MOVES = {[T.mouseMoved] = true, [T.leftMouseDragged] = true,
               [T.rightMouseDragged] = true, [T.otherMouseDragged] = true}

local function checkTarget(t)
    local front = hs.application.frontmostApplication()
    if not front or front:pid() ~= t.pid then return false, "app lost focus" end
    local win = hs.window.focusedWindow()
    if not win or win:id() ~= t.winID then return false, "window changed" end
    if not sameFrame(frameOf(win), t.frame) then return false, "window moved or resized" end
    if hs.spaces.focusedSpace() ~= t.space then return false, "space changed" end
    return true
end

-- Is this key event the stop hotkey?
local function isStopKey(ev)
    local spec, flags = obj.config.stopHotkey, ev:getFlags()
    if hs.keycodes.map[spec[2]] ~= ev:getKeyCode() then return false end
    for _, m in ipairs(spec[1]) do if not flags[m] then return false end end
    return true
end

---------------------------------------------------------------------------
-- guards

local function stopGuards()
    if obj._guardTimer then obj._guardTimer:stop(); obj._guardTimer = nil end
    if obj._appWatcher then obj._appWatcher:stop(); obj._appWatcher = nil end
    if obj._spaceWatcher then obj._spaceWatcher:stop(); obj._spaceWatcher = nil end
end

local function startGuards(target, onFail)
    stopGuards()
    local function fail(reason)
        stopGuards()
        onFail(reason)
    end
    obj._guardTimer = hs.timer.doEvery(obj.config.guardInterval, function()
        local ok, reason = checkTarget(target)
        if not ok then fail(reason) end
    end)
    obj._appWatcher = hs.application.watcher.new(function(name, event, app)
        local A = hs.application.watcher
        if event == A.activated and app and app:pid() ~= target.pid then
            fail("switched to " .. (name or "another app"))
        elseif (event == A.deactivated or event == A.terminated) and app and app:pid() == target.pid then
            fail("app lost focus")
        end
    end)
    obj._appWatcher:start()
    obj._spaceWatcher = hs.spaces.watcher.new(function() fail("space changed") end)
    obj._spaceWatcher:start()
end

---------------------------------------------------------------------------
-- recording

local function beginRecording()
    local target = snapshotTarget()
    if not target then
        setState("idle")
        return alert("⏺ No focused window to record")
    end

    local jump = centerMouse(target)
    local events, keysDown, buttonsDown = {}, {}, {}
    local start = now()

    obj._recTarget = target
    obj._recEvents = events
    obj._recStart = start
    obj._tap = hs.eventtap.new(CAPTURE, function(ev)
        local ty = ev:getType()
        if ev:getProperty(P.eventSourceUserData) == MAGIC then return false end -- our centring
        if MOVES[ty] and jump then
            -- First real move after centring carries the jump; take it back out.
            local copy = ev:copy()
            copy:setProperty(P.mouseEventDeltaX, ev:getProperty(P.mouseEventDeltaX) - jump.x)
            copy:setProperty(P.mouseEventDeltaY, ev:getProperty(P.mouseEventDeltaY) - jump.y)
            jump = nil
            events[#events + 1] = {t = now() - start, ev = copy}
            return false
        end
        if ty == T.keyDown or ty == T.keyUp then
            if isStopKey(ev) then return false end
            local code = ev:getKeyCode()
            if ty == T.keyDown then
                keysDown[code] = true
            elseif keysDown[code] then
                keysDown[code] = nil
            else
                return false -- release of a key pressed before recording began
            end
        elseif UP_OF[ty] then
            buttonsDown[ty] = true
        elseif DOWN_OF[ty] then
            if not buttonsDown[DOWN_OF[ty]] then return false end
            buttonsDown[DOWN_OF[ty]] = nil
        end
        events[#events + 1] = {t = now() - start, ev = ev:copy()}
        return false
    end)

    setState("recording")
    obj._tap:start()
    startGuards(target, function(reason) obj.abortRecording(reason) end)
    setIndicator("⏺", "Recording " .. target.appName)
    alert("⏺ Recording " .. target.appName, 1)
end

local function teardownRecording()
    if obj._tap then obj._tap:stop(); obj._tap = nil end
    stopGuards()
    clearIndicator()
    obj._recEvents, obj._recTarget, obj._recStart = nil, nil, nil
    setState("idle")
end

function obj.finishRecording()
    if obj._state ~= "recording" then return end
    if obj._tap then obj._tap:stop() end
    local events, target = obj._recEvents, obj._recTarget
    local duration = now() - obj._recStart

    -- Drop the modifier presses that led up to the stop hotkey, and end the loop there.
    while #events > 0 and events[#events].ev:getType() == T.flagsChanged do
        duration = events[#events].t
        table.remove(events)
    end
    teardownRecording()

    if #events == 0 then return alert("⏺ Nothing recorded") end
    obj._rec = {
        bundleID = target.bundleID, appName = target.appName, frame = target.frame,
        duration = duration, events = events, recordedAt = os.date("%Y-%m-%d %H:%M:%S"),
    }
    local saved = obj.save("last")
    alert(string.format("⏹ Recorded %d events, %.1fs%s",
        #events, duration / 1e9, saved and "" or " (save failed — see console)"), 2)
end

function obj.abortRecording(reason)
    if obj._state ~= "recording" then return end
    teardownRecording()
    alert("⏺ Recording discarded: " .. (reason or "aborted"), 2.5)
end

---------------------------------------------------------------------------
-- playback

local held = {keys = {}, buttons = {}, flags = {}}

local function post(ev)
    local ty = ev:getType()
    if ty == T.keyDown then held.keys[ev:getKeyCode()] = true
    elseif ty == T.keyUp then held.keys[ev:getKeyCode()] = nil
    elseif UP_OF[ty] then held.buttons[ty] = true
    elseif DOWN_OF[ty] then held.buttons[DOWN_OF[ty]] = nil
    elseif ty == T.flagsChanged then held.flags = ev:getFlags()
    end
    ev:setProperty(P.eventSourceUserData, MAGIC)
    ev:post()
end

-- While playing, swallow mouse movement that did not come from us: it carries the
-- jump folded in by centring, and any accidental nudge would desync the replay.
-- Buttons and scroll are left alone, so a real click still works.
local function startMouseShield()
    if obj._shield then obj._shield:stop() end
    obj._shield = hs.eventtap.new({T.mouseMoved, T.leftMouseDragged, T.rightMouseDragged, T.otherMouseDragged},
        function(ev) return ev:getProperty(P.eventSourceUserData) ~= MAGIC end)
    obj._shield:start()
end

local function stopMouseShield()
    if obj._shield then obj._shield:stop(); obj._shield = nil end
end

-- Release everything the replay left pressed. Each post is pcall'd: one bad
-- release must not prevent the others.
local function releaseHeld()
    local E = hs.eventtap.event
    for code in pairs(held.keys) do
        pcall(function() E.newKeyEvent({}, code, false):post() end)
    end
    local pos = hs.mouse.absolutePosition()
    for downTy in pairs(held.buttons) do
        pcall(function() E.newMouseEvent(UP_OF[downTy], pos):post() end)
    end
    for _, m in ipairs(MODS) do
        if held.flags[m] then pcall(function() E.newKeyEvent({}, m, false):post() end) end
    end
    held = {keys = {}, buttons = {}, flags = {}}
end

local function updatePlayIndicator()
    local p = obj._play
    local limit = p.limit > 0 and ("/" .. p.limit) or ""
    setIndicator("▶" .. (p.loop + 1) .. limit, "Replaying in " .. p.target.appName)
end

local function tick()
    local p = obj._play
    if not p then return end
    p.timer = nil
    local evs, gapNs = obj._rec.events, obj.config.loopGap * 1e9
    local elapsed = now() - p.loopStart

    if p.i <= #evs and evs[p.i].t <= elapsed then
        -- Cheap check before every batch; the guard poll covers window and space.
        local front = hs.application.frontmostApplication()
        if not front or front:pid() ~= p.target.pid then return obj.stopPlayback("app lost focus") end
        while p.i <= #evs and evs[p.i].t <= elapsed do
            post(evs[p.i].ev)
            p.i = p.i + 1
        end
    end

    local nextDue
    if p.i <= #evs then
        nextDue = evs[p.i].t
    elseif elapsed >= obj._rec.duration then
        releaseHeld()
        p.loop = p.loop + 1
        if p.limit > 0 and p.loop >= p.limit then return obj.stopPlayback(nil) end
        updatePlayIndicator()
        centerMouse(p.target)
        p.loopStart = now() + gapNs
        p.i = 1
        p.timer = hs.timer.doAfter((gapNs + evs[1].t) / 1e9, tick)
        return
    else
        nextDue = obj._rec.duration
    end
    p.timer = hs.timer.doAfter(math.max(0, (nextDue - elapsed) / 1e9), tick)
end

local function beginPlayback(limit)
    setState("idle")
    local rec = obj._rec
    local target = snapshotTarget()
    if not target then return alert("▶ No focused window") end
    if target.bundleID ~= rec.bundleID then
        return alert("▶ This recording is for " .. rec.appName .. ", not " .. target.appName, 2.5)
    end
    if not sameFrame(target.frame, rec.frame) then
        alert("▶ Window is not where it was when recorded — clicks may miss", 3)
    end

    obj._play = {target = target, limit = limit or obj.config.loops, loop = 0, i = 1, loopStart = now()}
    setState("playing")
    startGuards(target, function(reason) obj.stopPlayback(reason) end)
    updatePlayIndicator()
    startMouseShield()
    centerMouse(target)
    tick()
end

function obj.stopPlayback(reason)
    if obj._state ~= "playing" then return end
    local p = obj._play
    if p and p.timer then p.timer:stop() end
    obj._play = nil
    stopGuards()
    stopMouseShield()
    releaseHeld()
    clearIndicator()
    setState("idle")
    local loops = p and p.loop or 0
    if reason then
        alert(string.format("■ Stopped after %d loop%s: %s", loops, loops == 1 and "" or "s", reason), 2.5)
    else
        alert(string.format("✓ Done: %d loop%s", loops, loops == 1 and "" or "s"), 2)
    end
end

---------------------------------------------------------------------------
-- actions (Hermes calls record/play over IPC; the stop hotkey calls halt)

function obj.record()
    if obj._state ~= "idle" then return alert("⏺ Busy: " .. obj._state) end
    setState("arming")
    alert("⏺ Recording starts once you let go…", 1)
    arm(beginRecording)
end

function obj.play(limit)
    if obj._state ~= "idle" then return alert("▶ Busy: " .. obj._state) end
    if not obj._rec then return alert("▶ Nothing recorded yet") end
    setState("arming")
    arm(function() beginPlayback(limit) end)
end

-- Stop whatever is happening. A recording is kept (this is the normal way to end one).
function obj.halt()
    cancelArming()
    if obj._state == "recording" then obj.finishRecording()
    elseif obj._state == "playing" then obj.stopPlayback("stopped")
    else
        setState("idle")
        releaseHeld()
        clearIndicator()
    end
end

function obj.showStatus() alert(obj.status(), 3) end

---------------------------------------------------------------------------
-- persistence

local function pathFor(name)
    name = tostring(name or "last")
    if not name:match("^[%w_%-]+$") then return nil, "bad name: " .. name end
    return obj.config.dir .. "/" .. name .. ".json"
end

local function ensureDir(dir)
    local acc = ""
    for part in dir:gmatch("[^/]+") do
        acc = acc .. "/" .. part
        if not hs.fs.attributes(acc) then hs.fs.mkdir(acc) end
    end
end

function obj.save(name)
    if not obj._rec then return nil, "nothing recorded" end
    local path, err = pathFor(name)
    if not path then return nil, err end
    ensureDir(obj.config.dir)
    local rec = obj._rec
    local out = {
        version = 1, bundleID = rec.bundleID, appName = rec.appName, frame = rec.frame,
        duration = rec.duration, recordedAt = rec.recordedAt, events = {},
    }
    for i, e in ipairs(rec.events) do
        out.events[i] = {t = e.t, d = hs.base64.encode(e.ev:asData())}
    end
    if not hs.json.write(out, path, false, true) then
        hs.printf("[macro] failed to write %s", path)
        return nil, "write failed: " .. path
    end
    return path
end

function obj.load(name)
    if obj._state ~= "idle" then return nil, "busy: " .. obj._state end
    local path, err = pathFor(name)
    if not path then return nil, err end
    if not hs.fs.attributes(path) then return nil, "no such recording: " .. path end
    local data = hs.json.read(path)
    if not data or data.version ~= 1 then return nil, "unreadable recording: " .. path end
    local events = {}
    for i, e in ipairs(data.events) do
        events[i] = {t = e.t, ev = hs.eventtap.event.newEventFromData(hs.base64.decode(e.d))}
    end
    obj._rec = {
        bundleID = data.bundleID, appName = data.appName, frame = data.frame,
        duration = data.duration, recordedAt = data.recordedAt, events = events,
    }
    return string.format("%s: %d events, %.1fs, %s", name or "last", #events, data.duration / 1e9, data.appName)
end

function obj.list()
    local names = {}
    if hs.fs.attributes(obj.config.dir) then
        for f in hs.fs.dir(obj.config.dir) do
            local n = f:match("^(.+)%.json$")
            if n then names[#names + 1] = n end
        end
    end
    table.sort(names)
    return table.concat(names, "\n")
end

function obj.status()
    local r = obj._rec
    local recDesc = r and string.format("%d events, %.1fs, %s (recorded %s)",
        #r.events, r.duration / 1e9, r.appName, r.recordedAt or "?") or "none"
    local s = "state: " .. obj._state .. "\nrecording: " .. recDesc
    if obj._play then s = s .. "\nloop: " .. (obj._play.loop + 1) end
    return s
end

---------------------------------------------------------------------------
-- seed interface

function obj:start(config)
    for k, v in pairs(config or {}) do obj.config[k] = v end
    local spec = obj.config.stopHotkey
    obj._stopKey = hs.hotkey.new(spec[1], spec[2], obj.halt) -- enabled by setState
    if not obj._rec then pcall(obj.load, "last") end
    return self
end

function obj:stop()
    cancelArming()
    if obj._state == "recording" then obj.abortRecording("reloaded")
    elseif obj._state == "playing" then obj.stopPlayback("reloaded") end
    if obj._stopKey then obj._stopKey:delete(); obj._stopKey = nil end
end

return obj
