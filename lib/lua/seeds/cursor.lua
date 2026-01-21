-- Cursor Overlay Seed
-- Draws a visible cursor indicator for remote desktop situations where the native cursor is invisible
local obj = {}

obj._canvas = nil
obj._mouseTap = nil
obj._enabled = false
obj._hotkey = nil

-- Configuration defaults
local config = {
    size = 24,           -- diameter of cursor indicator
    strokeWidth = 2,
    strokeColor = {red = 1, green = 0.2, blue = 0.2, alpha = 0.9},
    fillColor = {red = 1, green = 0.2, blue = 0.2, alpha = 0.3},
    style = "crosshair", -- "circle", "crosshair", or "ring"
    hotkey = {{"cmd", "ctrl"}, "m"}
}

local function createCanvas()
    local size = config.size
    local canvas = hs.canvas.new({x = 0, y = 0, w = size, h = size})
    canvas:level(hs.canvas.windowLevels.cursor + 1)
    canvas:behavior(hs.canvas.windowBehaviors.canJoinAllSpaces + hs.canvas.windowBehaviors.stationary)
    canvas:clickActivating(false)

    if config.style == "circle" then
        -- Filled circle
        canvas[1] = {
            type = "circle",
            action = "fill",
            center = {x = size/2, y = size/2},
            radius = size/2 - 2,
            fillColor = config.fillColor
        }
        canvas[2] = {
            type = "circle",
            action = "stroke",
            center = {x = size/2, y = size/2},
            radius = size/2 - 2,
            strokeColor = config.strokeColor,
            strokeWidth = config.strokeWidth
        }
    elseif config.style == "crosshair" then
        -- Crosshair with center dot
        local center = size / 2
        local armLength = size / 2 - 2
        -- Horizontal line
        canvas[1] = {
            type = "segments",
            action = "stroke",
            coordinates = {
                {x = 0, y = center},
                {x = center - 4, y = center},
            },
            strokeColor = config.strokeColor,
            strokeWidth = config.strokeWidth
        }
        canvas[2] = {
            type = "segments",
            action = "stroke",
            coordinates = {
                {x = center + 4, y = center},
                {x = size, y = center},
            },
            strokeColor = config.strokeColor,
            strokeWidth = config.strokeWidth
        }
        -- Vertical line
        canvas[3] = {
            type = "segments",
            action = "stroke",
            coordinates = {
                {x = center, y = 0},
                {x = center, y = center - 4},
            },
            strokeColor = config.strokeColor,
            strokeWidth = config.strokeWidth
        }
        canvas[4] = {
            type = "segments",
            action = "stroke",
            coordinates = {
                {x = center, y = center + 4},
                {x = center, y = size},
            },
            strokeColor = config.strokeColor,
            strokeWidth = config.strokeWidth
        }
        -- Center dot
        canvas[5] = {
            type = "circle",
            action = "fill",
            center = {x = center, y = center},
            radius = 2,
            fillColor = config.strokeColor
        }
    else -- ring
        canvas[1] = {
            type = "circle",
            action = "stroke",
            center = {x = size/2, y = size/2},
            radius = size/2 - 2,
            strokeColor = config.strokeColor,
            strokeWidth = config.strokeWidth
        }
    end

    return canvas
end

local function updatePosition()
    if not obj._canvas then return end
    local pos = hs.mouse.absolutePosition()
    local size = config.size
    obj._canvas:topLeft({x = pos.x - size/2, y = pos.y - size/2})
end

local function enable()
    if obj._enabled then return end

    obj._canvas = createCanvas()
    obj._canvas:show()

    obj._mouseTap = hs.eventtap.new({hs.eventtap.event.types.mouseMoved}, function(event)
        updatePosition()
        return false
    end)
    obj._mouseTap:start()

    -- Initial position
    updatePosition()

    obj._enabled = true
    hs.alert.show("Cursor overlay ON", 0.5)
end

local function disable()
    if not obj._enabled then return end

    if obj._mouseTap then
        obj._mouseTap:stop()
        obj._mouseTap = nil
    end

    if obj._canvas then
        obj._canvas:delete()
        obj._canvas = nil
    end

    obj._enabled = false
    hs.alert.show("Cursor overlay OFF", 0.5)
end

local function toggle()
    if obj._enabled then
        disable()
    else
        enable()
    end
end

function obj:start(userConfig)
    -- Merge user config
    if userConfig then
        for k, v in pairs(userConfig) do
            config[k] = v
        end
    end

    -- Bind hotkey
    local mods, key = table.unpack(config.hotkey)
    obj._hotkey = hs.hotkey.bind(mods, key, toggle)

    return self
end

function obj:stop()
    disable()

    if obj._hotkey then
        obj._hotkey:delete()
        obj._hotkey = nil
    end

    return self
end

-- Expose toggle for external use
obj.toggle = toggle
obj.enable = enable
obj.disable = disable

return obj
