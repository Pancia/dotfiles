local durp = require("lib/durationpicker")
local wake = require("lib/wakeDialog")

local obj = {}

obj.spoonPath = os.getenv("HOME").."/dotfiles/lib/lua/seeds/lotus/"

function timeConfig(x)
    local i = x.interval
    if not i then
        return { interval = 0, refreshRate = 10 }
    end
    if i.minutes then
        return { interval = i.minutes, refreshRate = 10 }
    else
        return { interval = i.seconds, refreshRate = 10 }
    end
end

-- Helper functions for dual-mode support
function hasIntervalMode()
    return obj.interval ~= nil
end

function hasClockMode()
    return obj.clockTriggers ~= nil
end

function getSortedClockTriggers()
    if not hasClockMode() then return {} end
    local triggers = {}
    for minute, soundIdx in pairs(obj.clockTriggers) do
        table.insert(triggers, {minute = minute, soundIdx = soundIdx})
    end
    table.sort(triggers, function(a, b) return a.minute < b.minute end)
    return triggers
end

function getNextClockTrigger(fromMinute)
    local triggers = getSortedClockTriggers()
    if #triggers == 0 then return nil end

    fromMinute = fromMinute or os.date("*t").min

    -- Find next trigger after current minute
    for _, trigger in ipairs(triggers) do
        if trigger.minute > fromMinute then
            local timeUntil = trigger.minute - fromMinute
            return {minute = trigger.minute, soundIdx = trigger.soundIdx, timeUntil = timeUntil}
        end
    end

    -- Wrap around to first trigger of next hour
    local firstTrigger = triggers[1]
    local timeUntil = (60 - fromMinute) + firstTrigger.minute
    return {minute = firstTrigger.minute, soundIdx = firstTrigger.soundIdx, timeUntil = timeUntil}
end

function isWithinTriggerWindow(currentMin, targetMin)
    -- Check if within ±1 minute of target
    local diff = math.abs(currentMin - targetMin)
    return diff <= 1
end

-- Trigger functions for interval and clock modes
function obj:triggerIntervalNotification()
    obj._state = "notif"
    local sound = obj.sounds[obj._intervalSoundIdx]
    if sound.notif then
        local notification = sound.notif()
        obj._notif = hs.notify.new(function()
            obj:onIntervalNotifCallback()
        end, notification):send()
        clearCheck = hs.timer.doEvery(1, function()
            if not hs.fnutils.contains(hs.notify.deliveredNotifications(), obj._notif) then
                if obj._notif:activationType() == hs.notify.activationTypes.none then
                    obj:onIntervalNotifCallback()
                end
                if clearCheck then
                    clearCheck:stop()
                    clearCheck = nil
                end
                obj._notif = nil
            end
        end)
    end
    obj:playAwarenessSound()
end

function obj:onIntervalNotifCallback()
    obj:stopAwarenessSound()
    obj._numTimesSoundPlayed = 0
    local sound = obj.sounds[obj._intervalSoundIdx]
    local action = sound.action
    local resume = function()
        obj._state = "countdown"
        obj._intervalTimeLeft = timeConfig(obj).interval
        obj._intervalSoundIdx = (obj._intervalSoundIdx % #obj.sounds) + 1
        obj:renderMenuBar()
    end
    if action then
        action(resume)
    else
        resume()
    end
end

function obj:triggerClockNotification(soundIdx, triggerMinute)
    obj._lastTriggeredMinute = triggerMinute
    local sound = obj.sounds[soundIdx]

    if sound.notif then
        local notification = sound.notif()
        local clockNotif = hs.notify.new(function()
            obj:onClockNotifCallback(soundIdx)
        end, notification):send()

        local clockClearCheck = hs.timer.doEvery(1, function()
            if not hs.fnutils.contains(hs.notify.deliveredNotifications(), clockNotif) then
                if clockNotif:activationType() == hs.notify.activationTypes.none then
                    obj:onClockNotifCallback(soundIdx)
                end
                if clockClearCheck then
                    clockClearCheck:stop()
                    clockClearCheck = nil
                end
                clockNotif = nil
            end
        end)
    end

    local volume = sound.volume or 1
    local s = sound.name
        and hs.sound.getByName(sound.name)
        or hs.sound.getByFile(obj.spoonPath.."/"..sound.path)
    local clockSound = s:volume(volume):play()
end

function obj:onClockNotifCallback(soundIdx)
    local sound = obj.sounds[soundIdx]
    local action = sound.action
    local resume = function()
        -- Clock mode just needs to clear the last triggered minute
        -- so it can trigger again next time
    end
    if action then
        action(resume)
    else
        resume()
    end
end

function obj:playAwarenessSound()
    if obj._numTimesSoundPlayed < 3 then
        obj._numTimesSoundPlayed = obj._numTimesSoundPlayed + 1
        local sound = obj.sounds[obj._intervalSoundIdx]
        local volume = sound.volume or 1
        local s = sound.name
        and hs.sound.getByName(sound.name)
        or hs.sound.getByFile(obj.spoonPath.."/"..sound.path)
        obj.lastPlayedSound = s:volume(volume):play()
    end
    return self
end

function obj:stopAwarenessSound()
    if obj.lastPlayedSound then
        obj.lastPlayedSound:stop()
        obj.lastPlayedSound = nil
    end
    return self
end

function obj:renderMenuBar()
    obj._menubar:setIcon(obj.spoonPath.."/lotus-flower.png")

    if obj._state == "sleeping" then
        obj._menubar:setTitle("zzz")
        return
    end

    local parts = {}

    -- Add interval info if active
    if hasIntervalMode() then
        local sound = obj.sounds[obj._intervalSoundIdx]
        local soundTitle = sound.name or sound.path:match("[^/]+$"):match("[^.]+")
        local timeLeft = math.ceil(obj._intervalTimeLeft)
        local intervalPart = timeLeft .. "/" .. timeConfig(obj).interval .. "[" .. obj._intervalSoundIdx .. "/" .. #obj.sounds .."]#" .. soundTitle
        table.insert(parts, intervalPart)
    end

    -- Add clock info if active
    if hasClockMode() then
        local nextTrigger = getNextClockTrigger()
        if nextTrigger then
            local sound = obj.sounds[nextTrigger.soundIdx]
            local soundTitle = sound.name or sound.path:match("[^/]+$"):match("[^.]+")
            local clockPart = "->" .. string.format(":%02d", nextTrigger.minute) .. "[" .. nextTrigger.soundIdx .. "]#" .. soundTitle
            table.insert(parts, clockPart)
        end
    end

    local title = table.concat(parts, " ")
    obj._menubar:setTitle(title)
end

function renderMenu()
    local menu = {}

    -- Add time option (only for interval mode)
    if hasIntervalMode() then
        table.insert(menu, {
            title = "add time to interval"
            , fn = function()
                obj.stopAwarenessSound()
                durp:show({
                    onDuration = function(duration)
                        obj._state = "countdown"
                        obj._intervalTimeLeft = obj._intervalTimeLeft + duration
                        obj:renderMenuBar()
                    end
                })
            end
        })
    end

    -- Restart interval option (only if interval mode)
    if hasIntervalMode() then
        table.insert(menu, {
            title = "restart interval"
            , fn = function()
                obj.stopAwarenessSound()
                hs.settings.set("state", nil)
                hs.settings.set("intervalSoundIdx", nil)
                hs.settings.set("intervalTimeLeft", nil)
                obj._state = "countdown"
                obj._intervalSoundIdx = 1
                obj._numTimesSoundPlayed = 0
                obj._intervalTimeLeft = timeConfig(obj).interval
                obj:renderMenuBar()
            end
        })
    end

    -- Reset clock triggers option (only if clock mode)
    if hasClockMode() then
        table.insert(menu, {
            title = "reset clock triggers"
            , fn = function()
                hs.settings.set("lastTriggeredMinute", nil)
                obj._lastTriggeredMinute = nil
                obj:renderMenuBar()
            end
        })
    end

    -- Restart all option (if both modes active)
    if hasIntervalMode() and hasClockMode() then
        table.insert(menu, {
            title = "restart all"
            , fn = function()
                obj.stopAwarenessSound()
                hs.settings.set("state", nil)
                hs.settings.set("intervalSoundIdx", nil)
                hs.settings.set("intervalTimeLeft", nil)
                hs.settings.set("lastTriggeredMinute", nil)
                obj._state = "countdown"
                obj._intervalSoundIdx = 1
                obj._numTimesSoundPlayed = 0
                obj._intervalTimeLeft = timeConfig(obj).interval
                obj._lastTriggeredMinute = nil
                obj:renderMenuBar()
            end
        })
    end

    return menu
end

function obj:notifCallback()
    obj.stopAwarenessSound()
    obj._numTimesSoundPlayed = 0
    local sound = obj.sounds[obj._intervalSoundIdx]
    local action = sound.action
    local resume = function()
        obj._state = "countdown"
        obj._intervalTimeLeft = timeConfig(obj).interval
        obj._intervalSoundIdx = (obj._intervalSoundIdx % #obj.sounds) + 1
        obj:renderMenuBar()
    end
    if action then
        action(resume)
    else
        resume()
    end
end

function with_default(obj, key, default)
    obj[key] = obj[key] or default
end

function obj:notify()
    local sound = obj.sounds[obj._intervalSoundIdx]
    if sound.notif then
        local notification = sound.notif()
        obj._notif = hs.notify.new(obj.notifCallback, notification):send()
        clearCheck = hs.timer.doEvery(1, function()
            if not hs.fnutils.contains(hs.notify.deliveredNotifications(), obj._notif) then
                if obj._notif:activationType() == hs.notify.activationTypes.none then
                    obj:notifCallback()
                end
                if clearCheck then
                    clearCheck:stop()
                    clearCheck = nil
                end
                obj._notif = nil
            end
        end)
    end
end

function obj:ensureNotifDelivered()
    obj._logger.df("[ensureNotifDelivered] state = %s", obj._state)
    if obj._state == "notif" and not obj._notif then
        obj:notify()
    end
    if obj._state ~= "sleeping" then
        obj:playAwarenessSound()
    end
end

function obj:heartbeat()
    -- Handle interval mode
    if hasIntervalMode() and obj._state ~= "sleeping" then
        if obj._state == "countdown" then
            obj._intervalTimeLeft = obj._intervalTimeLeft - 1
            if obj._intervalTimeLeft <= 0 then
                obj:triggerIntervalNotification()
            end
        elseif obj._state == "notif" then
            obj:ensureNotifDelivered()
        end
    end

    -- Handle clock mode
    if hasClockMode() and obj._state ~= "sleeping" then
        local currentMinute = os.date("*t").min
        local triggers = getSortedClockTriggers()

        -- Check if we should trigger any clock notifications
        for _, trigger in ipairs(triggers) do
            if isWithinTriggerWindow(currentMinute, trigger.minute) then
                -- Only trigger if we haven't already triggered this target minute
                if obj._lastTriggeredMinute ~= trigger.minute then
                    obj:triggerClockNotification(trigger.soundIdx, trigger.minute)
                end
                break
            end
        end

        -- Clear last triggered minute if we're far from any trigger
        local farFromAll = true
        for _, trigger in ipairs(triggers) do
            local diff = math.abs(currentMinute - trigger.minute)
            if diff <= 2 then
                farFromAll = false
                break
            end
        end
        if farFromAll and obj._lastTriggeredMinute then
            obj._lastTriggeredMinute = nil
        end
    end

    obj:renderMenuBar()
end

function onSleep()
    obj._logger.df("systemWillSleep, state: %s, prev: %s", obj._state, obj._prevState)
    obj._prevState = (obj._state ~= "sleeping" and obj._state or obj._prevState)
    obj._state = "sleeping"
    obj:renderMenuBar()
end

function onWake()
    obj._logger.df("systemDidWake -> state: %s, prev: %s", obj._state, obj._prevState)
    obj._state = (obj._prevState or obj._state)
    obj._prevState = nil

    -- Clear clock trigger state on wake to allow re-triggering
    if hasClockMode() then
        obj._lastTriggeredMinute = nil
    end

    obj:renderMenuBar()
end

function obj:start(config)
    obj._logger = hs.logger.new("Lotus", "debug")

    for k,v in pairs(config) do obj[k] = v end
    local saved = {
        ["state"] = hs.settings.get("state"),
        ["intervalSoundIdx"] = hs.settings.get("intervalSoundIdx"),
        ["intervalTimeLeft"] = hs.settings.get("intervalTimeLeft"),
        ["lastTriggeredMinute"] = hs.settings.get("lastTriggeredMinute"),
    }

    -- obj._logger.df("Started with: %s", hs.inspect(saved))

    obj._state = ("sleeping" ~= saved["state"] and saved["state"] or "countdown")
    obj._numTimesSoundPlayed = 0

    -- Initialize interval mode state
    if hasIntervalMode() then
        obj._intervalSoundIdx = saved["intervalSoundIdx"] or #obj.sounds
        obj._intervalTimeLeft = saved["intervalTimeLeft"] or timeConfig(obj).interval
        if not saved["intervalSoundIdx"] then
            obj:playAwarenessSound()
        end
    end

    -- Initialize clock mode state
    if hasClockMode() then
        obj._lastTriggeredMinute = saved["lastTriggeredMinute"]
    end

    obj._menubar = hs.menubar.new():setMenu(renderMenu)
    obj._heartbeat = hs.timer.doEvery(timeConfig(obj).refreshRate, obj.heartbeat)

    wake:onSleep(onSleep):onWake(onWake):start()

    obj:renderMenuBar()

    -- obj._logger.df("obj = %s", hs.inspect(obj))

    return self
end

function obj:saveState()
    hs.settings.set("state", obj._state)
    hs.settings.set("intervalSoundIdx", obj._intervalSoundIdx)
    hs.settings.set("intervalTimeLeft", obj._intervalTimeLeft)
    hs.settings.set("lastTriggeredMinute", obj._lastTriggeredMinute)
end

function obj:stop()
    obj:saveState()
    if obj._notif then
        obj._notif:withdraw()
    end
    if obj._heartbeat then
        obj._heartbeat:stop()
    end
    if obj._menubar then
      obj._menubar:delete()
    end
    return self
end

return obj
