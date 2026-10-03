-- Scroll Block
-- Swallows every scroll event while on — for the Magic Mouse, whose "wheel" is touch
-- on its surface and fires whenever a hand rests on it.
--
-- Why Hammerspoon and not Karabiner: Karabiner's mouse_basic `discard` only sees real
-- HID wheel events from a device it has grabbed. Magic Mouse scrolling is synthesized
-- by macOS from multitouch data, so there is nothing for Karabiner to discard, and
-- grabbing the mouse can break its gestures. An eventtap sits after all of that.
--
-- Not engaged from hammerspoon.lua on purpose. It is lazily required over IPC:
--     hs -c 'require("seeds.scrollblock").toggle()'
-- package.loaded keeps the module (and so the tap) alive between calls. A full
-- Hammerspoon reload resets it to OFF, which is the safe default. A soft reload
-- leaves it alone, since it isn't in softReload's seedModules list.
--
-- Blocks ALL scroll sources, trackpad included — CGEvents don't say which device
-- they came from. On this machine the Magic Mouse is the only pointer.
local obj = {}

obj._tap = nil
obj._menubar = nil

local function showIndicator()
    if obj._menubar then return end
    obj._menubar = hs.menubar.new()
    if not obj._menubar then return end
    obj._menubar:setTitle("🚫🖱")
    obj._menubar:setTooltip("Scrolling is blocked — click to re-enable")
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

function obj.on()
    if not obj._tap then
        obj._tap = hs.eventtap.new({hs.eventtap.event.types.scrollWheel}, function()
            return true -- true = delete the event
        end)
    end
    obj._tap:start()
    showIndicator()
    hs.alert.show("🖱 Scroll blocked", 1.2)
    return "on"
end

function obj.off()
    if obj._tap then obj._tap:stop() end
    hideIndicator()
    hs.alert.show("🖱 Scroll enabled", 1.2)
    return "off"
end

function obj.toggle()
    if obj.isOn() then return obj.off() else return obj.on() end
end

function obj.status()
    return obj.isOn() and "on" or "off"
end

-- Seed interface, in case it is ever engaged from hammerspoon.lua.
function obj:start(_config) return self end
function obj:stop()
    if obj._tap then obj._tap:stop(); obj._tap = nil end
    hideIndicator()
end

return obj
