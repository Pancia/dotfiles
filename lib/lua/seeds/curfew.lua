-- Curfew: wind-down reminder with hold-to-dismiss
-- Triggers every minute on the minute (XX:00)

local safeLogger = require("lib/safeLogger")

local obj = {}
obj._name = "curfew"
obj._logger = safeLogger.new("curfew", "info")

-- Configuration (set via start())
local config = {
    holdDuration = 15,   -- seconds to hold
}

-- State
obj._timer = nil
obj._overlays = {}  -- one overlay per screen
obj._holdStartTime = nil
obj._progressTimer = nil
obj._mouseDownTap = nil
obj._mouseUpTap = nil
obj._isShowing = false

function obj:scheduleNext()
    obj._timer = hs.timer.doAfter(60, function()
        obj:trigger()
        obj:scheduleNext()
    end)
end

function obj:createOverlayForScreen(screen)
    local frame = screen:frame()
    local fullFrame = screen:fullFrame()

    local boxWidth = 500
    local boxHeight = 350
    local centerX = frame.w / 2
    local centerY = frame.h / 2
    local boxX = centerX - boxWidth / 2
    local boxY = centerY - boxHeight / 2

    local overlay = hs.canvas.new(fullFrame)
    overlay:level(hs.canvas.windowLevels.screenSaver)
    overlay:behavior(hs.canvas.windowBehaviors.canJoinAllSpaces + hs.canvas.windowBehaviors.stationary)

    -- Full screen dim background
    overlay[1] = {
        type = "rectangle",
        action = "fill",
        fillColor = {red = 0.05, green = 0.05, blue = 0.1, alpha = 0.9}
    }

    -- Central dialog box
    overlay[2] = {
        type = "rectangle",
        action = "fill",
        frame = {x = boxX, y = boxY, w = boxWidth, h = boxHeight},
        fillColor = {red = 0.1, green = 0.1, blue = 0.15, alpha = 1},
        roundedRectRadii = {xRadius = 16, yRadius = 16}
    }

    -- Dialog border
    overlay[3] = {
        type = "rectangle",
        action = "stroke",
        frame = {x = boxX, y = boxY, w = boxWidth, h = boxHeight},
        strokeColor = {red = 0.4, green = 0.5, blue = 0.8, alpha = 1},
        strokeWidth = 2,
        roundedRectRadii = {xRadius = 16, yRadius = 16}
    }

    -- Layout positions (all relative to box)
    local ringCenterY = boxY + 210
    local ringRadius = 50

    -- Moon icon
    overlay[4] = {
        type = "circle",
        action = "fill",
        center = {x = centerX, y = boxY + 45},
        radius = 20,
        fillColor = {red = 0.9, green = 0.85, blue = 0.6, alpha = 1}
    }

    -- Title
    overlay[5] = {
        type = "text",
        text = "Time to wind down",
        textColor = {red = 1, green = 1, blue = 1, alpha = 1},
        textSize = 28,
        textAlignment = "center",
        frame = {x = boxX + 20, y = boxY + 80, w = boxWidth - 40, h = 40}
    }

    -- Time display
    overlay[6] = {
        type = "text",
        text = "It's " .. os.date("%I:%M %p"),
        textColor = {red = 0.6, green = 0.6, blue = 0.6, alpha = 1},
        textSize = 16,
        textAlignment = "center",
        frame = {x = boxX + 20, y = boxY + 115, w = boxWidth - 40, h = 25}
    }

    -- Progress ring background
    overlay[7] = {
        type = "circle",
        action = "stroke",
        center = {x = centerX, y = ringCenterY},
        radius = ringRadius,
        strokeColor = {red = 0.2, green = 0.2, blue = 0.25, alpha = 1},
        strokeWidth = 8
    }

    -- Progress ring (fills as you hold)
    overlay[8] = {
        id = "ringProgress",
        type = "arc",
        center = {x = centerX, y = ringCenterY},
        radius = ringRadius,
        startAngle = -90,
        endAngle = -90,
        strokeColor = {red = 0.4, green = 0.7, blue = 0.4, alpha = 1},
        strokeWidth = 8,
        action = "stroke"
    }

    -- Hold duration text
    overlay[9] = {
        id = "holdText",
        type = "text",
        text = "0/" .. config.holdDuration .. "s",
        textColor = {red = 0.8, green = 0.8, blue = 0.8, alpha = 1},
        textSize = 18,
        textAlignment = "center",
        frame = {x = centerX - 40, y = ringCenterY - 12, w = 80, h = 30}
    }

    -- Instructions
    overlay[10] = {
        type = "text",
        text = "Hold mouse button to dismiss",
        textColor = {red = 0.5, green = 0.5, blue = 0.5, alpha = 1},
        textSize = 14,
        textAlignment = "center",
        frame = {x = boxX + 20, y = boxY + boxHeight - 50, w = boxWidth - 40, h = 25}
    }

    overlay:clickActivating(false)
    overlay:show()

    return overlay
end

function obj:createOverlays()
    for _, screen in ipairs(hs.screen.allScreens()) do
        local overlay = obj:createOverlayForScreen(screen)
        table.insert(obj._overlays, overlay)
    end
end

function obj:updateProgress(elapsed)
    if #obj._overlays == 0 then return end

    local progress = math.min(elapsed / config.holdDuration, 1)
    local endAngle = -90 + (360 * progress)

    for _, overlay in ipairs(obj._overlays) do
        overlay[8].endAngle = endAngle
        overlay[9].text = string.format("%.0f/%ds", elapsed, config.holdDuration)
    end
end

function obj:resetProgress()
    if #obj._overlays == 0 then return end
    for _, overlay in ipairs(obj._overlays) do
        overlay[8].endAngle = -90
        overlay[9].text = "0/" .. config.holdDuration .. "s"
    end
end

function obj:startHold()
    obj._holdStartTime = hs.timer.secondsSinceEpoch()

    if obj._progressTimer then
        obj._progressTimer:stop()
    end

    obj._progressTimer = hs.timer.doEvery(0.05, function()
        if not obj._holdStartTime then return end

        local elapsed = hs.timer.secondsSinceEpoch() - obj._holdStartTime
        obj:updateProgress(elapsed)

        if elapsed >= config.holdDuration then
            obj:hide()
        end
    end)
end

function obj:endHold()
    obj._holdStartTime = nil

    if obj._progressTimer then
        obj._progressTimer:stop()
        obj._progressTimer = nil
    end

    obj:resetProgress()
end

function obj:setupEventTaps()
    obj._mouseDownTap = hs.eventtap.new({hs.eventtap.event.types.leftMouseDown}, function(event)
        if obj._isShowing then
            obj:startHold()
            return true
        end
        return false
    end)

    obj._mouseUpTap = hs.eventtap.new({hs.eventtap.event.types.leftMouseUp}, function(event)
        if obj._holdStartTime then
            obj:endHold()
            return true
        end
        return false
    end)

    obj._mouseDownTap:start()
    obj._mouseUpTap:start()
end

function obj:cleanupEventTaps()
    if obj._mouseDownTap then
        obj._mouseDownTap:stop()
        obj._mouseDownTap = nil
    end
    if obj._mouseUpTap then
        obj._mouseUpTap:stop()
        obj._mouseUpTap = nil
    end
end

function obj:isWithinCurfew()
    local hour = tonumber(os.date("%H"))
    local minute = tonumber(os.date("%M"))
    local now = hour * 60 + minute
    local trigger = config.triggerTime.hour * 60 + config.triggerTime.minute
    local reset = config.resetTime.hour * 60 + config.resetTime.minute

    -- Curfew spans midnight: trigger if now >= triggerTime OR now < resetTime
    return now >= trigger or now < reset
end

function obj:trigger()
    if obj._isShowing then return end
    if not obj:isWithinCurfew() then return end

    obj._logger.i("Showing curfew overlay")
    obj._isShowing = true

    obj:createOverlays()
    obj:setupEventTaps()
end

function obj:hide()
    obj._logger.i("Hiding curfew overlay")
    obj._isShowing = false
    obj:endHold()
    obj:cleanupEventTaps()

    for _, overlay in ipairs(obj._overlays) do
        overlay:delete()
    end
    obj._overlays = {}
end

function obj:start(cfg)
    obj._logger.i("Starting curfew monitor")

    -- Merge config
    if cfg then
        for k, v in pairs(cfg) do
            config[k] = v
        end
    end

    obj:scheduleNext()

    return obj
end

function obj:stop()
    obj._logger.i("Stopping curfew monitor")

    if obj._timer then
        obj._timer:stop()
        obj._timer = nil
    end

    obj:hide()
end

return obj
