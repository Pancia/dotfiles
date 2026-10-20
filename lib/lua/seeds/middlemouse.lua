-- Middle Mouse Key
-- Turns one keyboard key into the middle mouse button: press = otherMouseDown,
-- release = otherMouseUp, and moving the pointer while it is held sends
-- otherMouseDragged, so middle-drag (pan, orbit) works too. The key itself is
-- swallowed while bound.
--
-- Driven from the Hermes +utils submenu, lazily required over IPC like scrollblock:
--     hs -c 'require("seeds.middlemouse").bind("rightalt")'   -- hs.keycodes.map name or keycode
--     hs -c 'require("seeds.middlemouse").capture()'          -- next key pressed becomes it
--     hs -c 'require("seeds.middlemouse").off()'
-- A full Hammerspoon reload resets it to OFF; it isn't in softReload's seedModules list.
--
-- Modifier keys arrive as flagsChanged, not keyDown/keyUp. Their up/down state is
-- read from the device-dependent bits in rawFlags, so right ⌥ is told apart from
-- left ⌥ even while both are held.
--
-- Hammerspoon sees keys after Karabiner, so bind what Karabiner emits: right ⌘ is
-- remapped to left ⌘ there, and caps lock to left ctrl.
local obj = {}

local types = hs.eventtap.event.types
local props = hs.eventtap.event.properties

obj._keyCode = nil
obj._held = false
obj._keyTap = nil
obj._dragTap = nil
obj._captureTap = nil
obj._captureTimer = nil
obj._menubar = nil

-- NX_DEVICE*KEYMASK bits for each modifier keycode.
local MODIFIER_MASKS = {
    [59] = 0x000001, -- left ctrl
    [56] = 0x000002, -- left shift
    [60] = 0x000004, -- right shift
    [55] = 0x000008, -- left cmd
    [54] = 0x000010, -- right cmd
    [58] = 0x000020, -- left alt
    [61] = 0x000040, -- right alt
    [62] = 0x002000, -- right ctrl
    [63] = 0x800000, -- fn
}

local PRETTY = {
    [59] = "left ⌃", [62] = "right ⌃",
    [56] = "left ⇧", [60] = "right ⇧",
    [55] = "left ⌘", [54] = "right ⌘",
    [58] = "left ⌥", [61] = "right ⌥",
    [63] = "fn",
}

local function keyName(code)
    return PRETTY[code] or hs.keycodes.map[code] or ("keycode " .. tostring(code))
end

local function postButton(eventType, point)
    local e = hs.eventtap.event.newMouseEvent(eventType, point or hs.mouse.absolutePosition())
    e:setProperty(props.mouseEventButtonNumber, 2)
    e:setProperty(props.mouseEventClickState, 1)
    e:post()
end

local function press()
    if obj._held then return end -- key autorepeat
    obj._held = true
    postButton(types.otherMouseDown)
    obj._dragTap:start()
end

local function release()
    if not obj._held then return end
    obj._held = false
    obj._dragTap:stop()
    postButton(types.otherMouseUp)
end

local function onKey(event)
    local code = event:getKeyCode()
    if code ~= obj._keyCode then return false end
    local t = event:getType()
    if t == types.flagsChanged then
        local down = (event:rawFlags() & MODIFIER_MASKS[code]) ~= 0
        if down then press() else release() end
    elseif t == types.keyDown then
        press()
    elseif t == types.keyUp then
        release()
    end
    return true
end

local function onDrag(event)
    local drag = hs.eventtap.event.newMouseEvent(types.otherMouseDragged, event:location())
    drag:setProperty(props.mouseEventButtonNumber, 2)
    drag:setProperty(props.mouseEventDeltaX, event:getProperty(props.mouseEventDeltaX))
    drag:setProperty(props.mouseEventDeltaY, event:getProperty(props.mouseEventDeltaY))
    return true, { drag }
end

local function showIndicator()
    if not obj._menubar then
        obj._menubar = hs.menubar.new()
        if not obj._menubar then return end
        obj._menubar:setClickCallback(function() obj.off() end)
    end
    obj._menubar:setTitle("🖱³ " .. keyName(obj._keyCode))
    obj._menubar:setTooltip(keyName(obj._keyCode) .. " is the middle mouse button — click to unbind")
end

local function hideIndicator()
    if obj._menubar then
        obj._menubar:delete()
        obj._menubar = nil
    end
end

local function stopCapture()
    if obj._captureTap then obj._captureTap:stop(); obj._captureTap = nil end
    if obj._captureTimer then obj._captureTimer:stop(); obj._captureTimer = nil end
end

function obj.isOn()
    return obj._keyCode ~= nil and obj._keyTap ~= nil and obj._keyTap:isEnabled()
end

-- key: an hs.keycodes.map name ("rightalt", "`", "f5") or a raw keycode.
function obj.bind(key)
    local code = type(key) == "number" and key or hs.keycodes.map[key]
    if not code then
        hs.alert.show("🖱 Unknown key: " .. tostring(key), 2)
        return "unknown key: " .. tostring(key)
    end
    stopCapture()
    release()
    obj._keyCode = code
    if not obj._keyTap then
        obj._keyTap = hs.eventtap.new({ types.keyDown, types.keyUp, types.flagsChanged }, onKey)
        obj._dragTap = hs.eventtap.new({ types.mouseMoved }, onDrag)
    end
    obj._keyTap:start()
    showIndicator()
    hs.alert.show("🖱 " .. keyName(code) .. " → middle mouse", 1.5)
    return obj.status()
end

-- The next key pressed (modifiers included) becomes the middle mouse key.
-- Escape cancels; so does 10s of nothing.
function obj.capture()
    stopCapture()
    hs.alert.show("🖱 Press the key to use as middle mouse (esc cancels)", 3)
    obj._captureTap = hs.eventtap.new({ types.keyDown, types.flagsChanged }, function(event)
        local code = event:getKeyCode()
        if event:getType() == types.flagsChanged then
            local mask = MODIFIER_MASKS[code]
            if not mask or (event:rawFlags() & mask) == 0 then return false end
        end
        if code == 53 then
            stopCapture()
            hs.alert.show("🖱 Cancelled", 1)
            return true
        end
        -- Defer so the bound tap doesn't see this same press.
        hs.timer.doAfter(0, function() obj.bind(code) end)
        stopCapture()
        return true
    end)
    obj._captureTap:start()
    obj._captureTimer = hs.timer.doAfter(10, function()
        stopCapture()
        hs.alert.show("🖱 No key pressed — cancelled", 1.2)
    end)
    return "capturing"
end

function obj.off()
    stopCapture()
    release()
    if obj._keyTap then obj._keyTap:stop() end
    local was = obj._keyCode
    obj._keyCode = nil
    hideIndicator()
    if was then hs.alert.show("🖱 Middle mouse key unbound", 1.2) end
    return "off"
end

function obj.status()
    return obj.isOn() and ("on: " .. keyName(obj._keyCode)) or "off"
end

-- Seed interface, in case it is ever engaged from hammerspoon.lua.
function obj:start(_config) return self end
function obj:stop()
    obj.off()
    obj._keyTap, obj._dragTap = nil, nil
end

return obj
