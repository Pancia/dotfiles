-- Curfew: 9pm wind-down reminder with hold-to-dismiss
-- Simple polling approach: check every minute, show overlay if in curfew window

local obj = {}
obj._name = "curfew"
obj._logger = hs.logger.new("curfew", "info")

-- Configuration (set via start())
local config = {
    triggerHour = 21,    -- 9pm
    resetHour = 4,       -- 4am
    holdDuration = 15,   -- seconds to hold
    checkInterval = 60   -- check every 60 seconds
}

-- State
obj._timer = nil
obj._overlay = nil
obj._holdStartTime = nil
obj._progressTimer = nil
obj._mouseDownTap = nil
obj._mouseUpTap = nil
obj._isShowing = false

function obj:isInCurfewWindow()
    local hour = tonumber(os.date("%H"))
    return hour >= config.triggerHour or hour < config.resetHour
end

function obj:createOverlay()
    local screen = hs.screen.mainScreen()
    local frame = screen:frame()

    local boxWidth = 500
    local boxHeight = 350
    local centerX = frame.w / 2
    local centerY = frame.h / 2
    local boxX = centerX - boxWidth / 2
    local boxY = centerY - boxHeight / 2

    obj._overlay = hs.canvas.new(frame)
    obj._overlay:level(hs.canvas.windowLevels.screenSaver)
    obj._overlay:behavior(hs.canvas.windowBehaviors.canJoinAllSpaces + hs.canvas.windowBehaviors.stationary)

    -- Full screen dim background
    obj._overlay[1] = {
        type = "rectangle",
        action = "fill",
        fillColor = {red = 0.05, green = 0.05, blue = 0.1, alpha = 0.9}
    }

    -- Central dialog box
    obj._overlay[2] = {
        type = "rectangle",
        action = "fill",
        frame = {x = boxX, y = boxY, w = boxWidth, h = boxHeight},
        fillColor = {red = 0.1, green = 0.1, blue = 0.15, alpha = 1},
        roundedRectRadii = {xRadius = 16, yRadius = 16}
    }

    -- Dialog border
    obj._overlay[3] = {
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
    obj._overlay[4] = {
        type = "circle",
        action = "fill",
        center = {x = centerX, y = boxY + 45},
        radius = 20,
        fillColor = {red = 0.9, green = 0.85, blue = 0.6, alpha = 1}
    }

    -- Title
    obj._overlay[5] = {
        type = "text",
        text = "Time to wind down",
        textColor = {red = 1, green = 1, blue = 1, alpha = 1},
        textSize = 28,
        textAlignment = "center",
        frame = {x = boxX + 20, y = boxY + 80, w = boxWidth - 40, h = 40}
    }

    -- Time display
    obj._overlay[6] = {
        type = "text",
        text = "It's " .. os.date("%I:%M %p"),
        textColor = {red = 0.6, green = 0.6, blue = 0.6, alpha = 1},
        textSize = 16,
        textAlignment = "center",
        frame = {x = boxX + 20, y = boxY + 115, w = boxWidth - 40, h = 25}
    }

    -- Progress ring background
    obj._overlay[7] = {
        type = "circle",
        action = "stroke",
        center = {x = centerX, y = ringCenterY},
        radius = ringRadius,
        strokeColor = {red = 0.2, green = 0.2, blue = 0.25, alpha = 1},
        strokeWidth = 8
    }

    -- Progress ring (fills as you hold)
    obj._overlay[8] = {
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
    obj._overlay[9] = {
        id = "holdText",
        type = "text",
        text = "0/" .. config.holdDuration .. "s",
        textColor = {red = 0.8, green = 0.8, blue = 0.8, alpha = 1},
        textSize = 18,
        textAlignment = "center",
        frame = {x = centerX - 40, y = ringCenterY - 12, w = 80, h = 30}
    }

    -- Instructions
    obj._overlay[10] = {
        type = "text",
        text = "Hold mouse button to dismiss",
        textColor = {red = 0.5, green = 0.5, blue = 0.5, alpha = 1},
        textSize = 14,
        textAlignment = "center",
        frame = {x = boxX + 20, y = boxY + boxHeight - 50, w = boxWidth - 40, h = 25}
    }

    obj._overlay:clickActivating(false)
    obj._overlay:show()
end

function obj:updateProgress(elapsed)
    if not obj._overlay then return end

    local progress = math.min(elapsed / config.holdDuration, 1)
    local endAngle = -90 + (360 * progress)

    obj._overlay[8].endAngle = endAngle
    obj._overlay[9].text = string.format("%.0f/%ds", elapsed, config.holdDuration)
end

function obj:resetProgress()
    if not obj._overlay then return end
    obj._overlay[8].endAngle = -90
    obj._overlay[9].text = "0/" .. config.holdDuration .. "s"
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

function obj:trigger()
    if obj._isShowing then return end

    obj._logger.i("Showing curfew overlay")
    obj._isShowing = true

    obj:createOverlay()
    obj:setupEventTaps()
end

function obj:hide()
    obj._logger.i("Hiding curfew overlay")
    obj._isShowing = false
    obj:endHold()
    obj:cleanupEventTaps()

    if obj._overlay then
        obj._overlay:delete()
        obj._overlay = nil
    end
end

function obj:checkAndShow()
    if obj:isInCurfewWindow() and not obj._isShowing then
        obj:trigger()
    end
end

function obj:start(cfg)
    obj._logger.i("Starting curfew monitor")

    -- Merge config
    if cfg then
        for k, v in pairs(cfg) do
            config[k] = v
        end
    end

    -- Check every minute
    obj._timer = hs.timer.doEvery(config.checkInterval, function()
        obj:checkAndShow()
    end)

    -- Initial check after short delay
    hs.timer.doAfter(3, function()
        obj:checkAndShow()
    end)

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
