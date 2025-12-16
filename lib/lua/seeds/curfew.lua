-- Curfew: 9pm wind-down reminder with escalating hold-to-dismiss
local obj = {}
obj._name = "curfew"
obj._logger = hs.logger.new("curfew", "info")

-- Configuration (set via start())
local config = {
    triggerHour = 21,
    triggerMinute = 0,
    snoozeInterval = 15,  -- minutes
    resetHour = 4,
    holdDurations = {5, 10, 20, 40, 60}
}

-- State
obj._snoozeCount = 0
obj._overlay = nil
obj._holdStartTime = nil
obj._progressTimer = nil
obj._mouseDownTap = nil
obj._mouseUpTap = nil
obj._dailyTimer = nil
obj._snoozeTimer = nil
obj._sleepWatcher = nil
obj._isShowing = false

-- Colors by escalation level
local COLORS = {
    {bg = {red = 0.1, green = 0.1, blue = 0.15, alpha = 0.9}, ring = {red = 0.4, green = 0.5, blue = 0.8}},  -- Calm blue
    {bg = {red = 0.12, green = 0.1, blue = 0.15, alpha = 0.9}, ring = {red = 0.5, green = 0.5, blue = 0.7}}, -- Slightly brighter
    {bg = {red = 0.15, green = 0.12, blue = 0.1, alpha = 0.9}, ring = {red = 0.84, green = 0.62, blue = 0.18}}, -- Amber
    {bg = {red = 0.18, green = 0.1, blue = 0.1, alpha = 0.92}, ring = {red = 0.9, green = 0.3, blue = 0.3}},  -- Red
    {bg = {red = 0.2, green = 0.08, blue = 0.08, alpha = 0.95}, ring = {red = 1, green = 0.2, blue = 0.2}}   -- Deep red
}

local MESSAGES = {
    "Time to wind down",
    "Consider wrapping up",
    "It's getting late",
    "You should really stop",
    "Final warning"
}

function obj:getColorLevel()
    return math.min(obj._snoozeCount + 1, #COLORS)
end

function obj:getHoldDuration()
    return config.holdDurations[math.min(obj._snoozeCount + 1, #config.holdDurations)]
end

function obj:isInCurfewWindow()
    local hour = tonumber(os.date("%H"))
    return hour >= config.triggerHour or hour < config.resetHour
end

function obj:saveState()
    hs.settings.set("curfew.snoozeCount", obj._snoozeCount)
    hs.settings.set("curfew.lastDate", os.date("%Y-%m-%d"))
end

function obj:savePendingTrigger(triggerTime)
    hs.settings.set("curfew.nextTriggerTime", triggerTime)
    obj._logger.i("Saved pending trigger for " .. os.date("%H:%M:%S", triggerTime))
end

function obj:clearPendingTrigger()
    hs.settings.set("curfew.nextTriggerTime", nil)
end

function obj:getPendingTrigger()
    return hs.settings.get("curfew.nextTriggerTime")
end

function obj:loadState()
    local savedDate = hs.settings.get("curfew.lastDate")
    local today = os.date("%Y-%m-%d")

    -- Reset if new day (after reset hour)
    local hour = tonumber(os.date("%H"))
    if savedDate ~= today and hour >= config.resetHour and hour < config.triggerHour then
        obj._snoozeCount = 0
    else
        obj._snoozeCount = hs.settings.get("curfew.snoozeCount") or 0
    end
end

function obj:createOverlay()
    local screen = hs.screen.mainScreen()
    local frame = screen:frame()
    local level = obj:getColorLevel()
    local colors = COLORS[level]
    local holdDuration = obj:getHoldDuration()

    local boxWidth = 500
    local boxHeight = 400
    local centerX = frame.w / 2
    local centerY = frame.h / 2
    local boxX = centerX - boxWidth / 2
    local boxY = centerY - boxHeight / 2

    obj._overlay = hs.canvas.new(frame)
    obj._overlay:level(hs.canvas.windowLevels.screenSaver)
    obj._overlay:behavior(hs.canvas.windowBehaviors.canJoinAllSpaces + hs.canvas.windowBehaviors.stationary)

    -- Full screen dim background
    obj._overlay[1] = {
        id = "background",
        type = "rectangle",
        action = "fill",
        fillColor = colors.bg
    }

    -- Central dialog box
    obj._overlay[2] = {
        id = "dialog",
        type = "rectangle",
        action = "fill",
        frame = {x = boxX, y = boxY, w = boxWidth, h = boxHeight},
        fillColor = {red = 0.1, green = 0.1, blue = 0.12, alpha = 1},
        roundedRectRadii = {xRadius = 16, yRadius = 16}
    }

    -- Dialog border
    obj._overlay[3] = {
        id = "dialogBorder",
        type = "rectangle",
        action = "stroke",
        frame = {x = boxX, y = boxY, w = boxWidth, h = boxHeight},
        strokeColor = colors.ring,
        strokeWidth = 2,
        roundedRectRadii = {xRadius = 16, yRadius = 16}
    }

    -- Moon icon (simple circle)
    obj._overlay[4] = {
        id = "moonIcon",
        type = "circle",
        action = "fill",
        center = {x = centerX, y = boxY + 60},
        radius = 25,
        fillColor = {red = 0.9, green = 0.85, blue = 0.6, alpha = 1}
    }

    -- Title
    obj._overlay[5] = {
        id = "title",
        type = "text",
        text = MESSAGES[level],
        textColor = {red = 1, green = 1, blue = 1, alpha = 1},
        textSize = 32,
        textAlignment = "center",
        frame = {x = boxX + 20, y = boxY + 100, w = boxWidth - 40, h = 45}
    }

    -- Time display
    obj._overlay[6] = {
        id = "timeText",
        type = "text",
        text = "It's " .. os.date("%I:%M %p"),
        textColor = {red = 0.7, green = 0.7, blue = 0.7, alpha = 1},
        textSize = 18,
        textAlignment = "center",
        frame = {x = boxX + 20, y = boxY + 145, w = boxWidth - 40, h = 30}
    }

    -- Progress ring background (full circle)
    obj._overlay[7] = {
        id = "ringBg",
        type = "circle",
        action = "stroke",
        center = {x = centerX, y = centerY + 20},
        radius = 55,
        strokeColor = {red = 0.2, green = 0.2, blue = 0.25, alpha = 1},
        strokeWidth = 10
    }

    -- Progress ring (will be updated during hold)
    obj._overlay[8] = {
        id = "ringProgress",
        type = "arc",
        center = {x = centerX, y = centerY + 20},
        radius = 55,
        startAngle = -90,
        endAngle = -90,  -- Will grow to 270 (full circle)
        strokeColor = colors.ring,
        strokeWidth = 10,
        action = "stroke"
    }

    -- Hold duration text (inside ring)
    obj._overlay[9] = {
        id = "holdText",
        type = "text",
        text = "0/" .. holdDuration .. "s",
        textColor = {red = 0.8, green = 0.8, blue = 0.8, alpha = 1},
        textSize = 20,
        textAlignment = "center",
        frame = {x = centerX - 50, y = centerY + 5, w = 100, h = 30}
    }

    -- Instructions
    obj._overlay[10] = {
        id = "instructions",
        type = "text",
        text = "Hold mouse button to dismiss",
        textColor = {red = 0.5, green = 0.5, blue = 0.5, alpha = 1},
        textSize = 14,
        textAlignment = "center",
        frame = {x = boxX + 20, y = boxY + boxHeight - 80, w = boxWidth - 40, h = 25}
    }

    -- Snooze count
    obj._overlay[11] = {
        id = "snoozeCount",
        type = "text",
        text = obj._snoozeCount > 0 and ("Snooze #" .. obj._snoozeCount) or "",
        textColor = {red = 0.4, green = 0.4, blue = 0.4, alpha = 1},
        textSize = 12,
        textAlignment = "center",
        frame = {x = boxX + 20, y = boxY + boxHeight - 50, w = boxWidth - 40, h = 20}
    }

    obj._overlay:clickActivating(false)
    obj._overlay:show()
end

function obj:updateProgress(elapsed)
    if not obj._overlay then return end

    local holdDuration = obj:getHoldDuration()
    local progress = math.min(elapsed / holdDuration, 1)
    local endAngle = -90 + (360 * progress)

    -- Update arc
    obj._overlay[8].endAngle = endAngle

    -- Update text
    obj._overlay[9].text = string.format("%.0f/%ds", elapsed, holdDuration)
end

function obj:resetProgress()
    if not obj._overlay then return end
    obj._overlay[8].endAngle = -90
    obj._overlay[9].text = "0/" .. obj:getHoldDuration() .. "s"
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

        if elapsed >= obj:getHoldDuration() then
            obj:snooze()
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
            return true  -- Consume event
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
    if obj._isShowing then
        obj._logger.i("Already showing, skipping trigger")
        return
    end

    obj._logger.i("Triggering curfew overlay (snooze count: " .. obj._snoozeCount .. ")")
    obj._isShowing = true

    obj:createOverlay()
    obj:setupEventTaps()
end

function obj:hide()
    obj._isShowing = false
    obj:endHold()
    obj:cleanupEventTaps()

    if obj._overlay then
        obj._overlay:delete()
        obj._overlay = nil
    end
end

function obj:snooze()
    obj._logger.i("Snoozing, will return in " .. config.snoozeInterval .. " minutes")
    obj:hide()

    obj._snoozeCount = obj._snoozeCount + 1
    obj:saveState()

    -- Calculate and persist next trigger time
    local nextTriggerTime = os.time() + (config.snoozeInterval * 60)
    obj:savePendingTrigger(nextTriggerTime)

    -- Schedule next trigger
    obj:scheduleNextTrigger(config.snoozeInterval * 60)
end

function obj:scheduleNextTrigger(delaySeconds)
    if obj._snoozeTimer then
        obj._snoozeTimer:stop()
    end

    obj._snoozeTimer = hs.timer.doAfter(delaySeconds, function()
        obj:clearPendingTrigger()
        if obj:isInCurfewWindow() then
            obj:trigger()
        end
    end)
end

function obj:start(cfg)
    obj._logger.i("Starting curfew monitor")

    -- Merge config
    if cfg then
        for k, v in pairs(cfg) do
            config[k] = v
        end
    end

    obj:loadState()

    -- 1. Daily trigger at configured time
    local triggerTime = string.format("%02d:%02d", config.triggerHour, config.triggerMinute)
    obj._dailyTimer = hs.timer.doAt(triggerTime, "1d", function()
        obj._snoozeCount = 0  -- Reset on fresh trigger
        obj:saveState()
        obj:clearPendingTrigger()
        obj:trigger()
    end, true)  -- continueOnError = true

    -- 2. Check for pending snooze trigger (survives reload)
    local pendingTrigger = obj:getPendingTrigger()
    if pendingTrigger and obj:isInCurfewWindow() then
        local now = os.time()
        local remaining = pendingTrigger - now

        if remaining <= 0 then
            -- Trigger time already passed, trigger now
            obj._logger.i("Pending trigger time passed, triggering now")
            obj:clearPendingTrigger()
            hs.timer.doAfter(1, function()
                obj:trigger()
            end)
        else
            -- Schedule for remaining time
            obj._logger.i("Restoring pending trigger in " .. remaining .. " seconds")
            obj:scheduleNextTrigger(remaining)
        end
    elseif obj:isInCurfewWindow() then
        -- 3. No pending trigger but in curfew window - trigger fresh
        obj._logger.i("Starting in curfew window, triggering after delay")
        hs.timer.doAfter(3, function()
            obj:trigger()
        end)
    end

    -- 4. Watch for wake from sleep
    obj._sleepWatcher = hs.caffeinate.watcher.new(function(event)
        if event == hs.caffeinate.watcher.systemDidWake then
            obj._logger.i("System woke from sleep")
            if obj:isInCurfewWindow() and not obj._isShowing then
                -- Check for pending trigger first
                local pending = obj:getPendingTrigger()
                if pending then
                    local remaining = pending - os.time()
                    if remaining <= 0 then
                        obj._logger.i("Pending trigger passed during sleep, triggering")
                        obj:clearPendingTrigger()
                        hs.timer.doAfter(2, function()
                            obj:trigger()
                        end)
                    else
                        obj._logger.i("Restoring pending trigger after wake: " .. remaining .. "s")
                        obj:scheduleNextTrigger(remaining)
                    end
                else
                    hs.timer.doAfter(2, function()
                        obj:trigger()
                    end)
                end
            end
        end
    end)
    obj._sleepWatcher:start()

    return obj
end

function obj:stop()
    obj._logger.i("Stopping curfew monitor")

    obj:hide()

    if obj._dailyTimer then
        obj._dailyTimer:stop()
        obj._dailyTimer = nil
    end

    if obj._snoozeTimer then
        obj._snoozeTimer:stop()
        obj._snoozeTimer = nil
    end

    if obj._sleepWatcher then
        obj._sleepWatcher:stop()
        obj._sleepWatcher = nil
    end

    obj:saveState()
end

return obj
