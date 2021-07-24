local durp = require("lib/durationpicker")

local obj = {}

obj.spoonPath = os.getenv("HOME").."/dotfiles/lib/fennel/seeds/lotus/"

obj.interval = { minutes = 30 }

function timeConfig(x)
    local i = x.interval
    if i.minutes then
        return { interval = i.minutes, refreshRate = 60 }
    else
        return { interval = i.seconds, refreshRate = 1 }
    end
end

function obj:playAwarenessSound()
    if obj._numTimesSoundPlayed < 3 then
        obj._numTimesSoundPlayed = obj._numTimesSoundPlayed + 1
        local sound = obj.sounds[obj._soundIdx]
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
    local sound = obj.sounds[obj._soundIdx]
    obj._menubar:setIcon(obj.spoonPath.."/lotus-flower.png")
    local soundTitle = sound.name or sound.path:match("[^/]+$"):match("[^.]+")
    local timeLeft = math.ceil(obj._timeLeft)
    local title = timeLeft .. "->[" .. obj._soundIdx .. "/" .. #obj.sounds .."]#" .. soundTitle
    obj._menubar:setTitle(title)
end

function renderMenu()
    return {
        {title = "add time"
        , fn = function()
            obj.stopAwarenessSound()
            durp:show({
                onDuration = function(duration)
                    obj._state = "countdown"
                    obj._timeLeft = obj._timeLeft + duration
                    obj:renderMenuBar()
                end
            })
        end},
        {title = "restart"
        , fn = function()
            obj.stopAwarenessSound()
            obj._state = "countdown"
            obj._soundIdx = 1
            obj._numTimesSoundPlayed = 0
            obj:renderMenuBar()
        end},
    }
end

function obj:notifCallback()
    obj.stopAwarenessSound()
    obj._numTimesSoundPlayed = 0
    local sound = obj.sounds[obj._soundIdx]
    local action = sound.action
    local resume = function()
        obj._state = "countdown"
        obj._timeLeft = timeConfig(obj).interval
        obj._soundIdx = (obj._soundIdx % #obj.sounds) + 1
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
    local sound = obj.sounds[obj._soundIdx]
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
    obj._logger.df("HeartBeat state = %s, ", obj._state)
    if obj._state == "countdown" then
        obj._timeLeft = obj._timeLeft - 1
        if obj._timeLeft <= 0 then
            obj._state = "notif"
            obj:notify()
            obj:playAwarenessSound()
        end
    elseif obj._state == "notif" then
        obj:ensureNotifDelivered()
    elseif obj._state == "sleeping" then
    else
        obj._logger.ef("UNEXPECTED STATE: %s", hs.inspect(obj._state))
    end
    obj:renderMenuBar()
end

function watchSystem(eventType)
    if eventType == hs.caffeinate.watcher.systemDidWake then
        obj._logger.df("systemDidWake")
        obj._state = obj._prevState
        obj._prevState = nil
    elseif eventType == hs.caffeinate.watcher.systemWillSleep then
        obj._logger.df("systemWillSleep")
        obj._prevState = obj._state
        obj._state = "sleeping"
    end
end

function obj:start(config)
    obj._logger = hs.logger.new("Lotus", "debug")

    for k,v in pairs(config) do obj[k] = v end
    local saved = {
        ["state"] = hs.settings.get("state"),
        ["soundIdx"] = hs.settings.get("soundIdx"),
        ["timeLeft"] = hs.settings.get("timeLeft"),
    }

    obj._logger.f("Started with: %s", hs.inspect(saved))

    obj._state = saved["state"] or "countdown"
    obj._numTimesSoundPlayed = 0
    obj._soundIdx = saved["soundIdx"] or #obj.sounds
    obj._timeLeft = saved["timeLeft"] or timeConfig(obj).interval

    if not saved["soundIdx"] then
        obj:playAwarenessSound()
    end

    obj._menubar = hs.menubar.new():setMenu(renderMenu)
    obj._heartbeat = hs.timer.doEvery(timeConfig(obj).refreshRate, obj.heartbeat)
    obj._systemWatcher = hs.caffeinate.watcher.new(watchSystem):start()

    obj:renderMenuBar()

    obj._logger.f("obj = %s", hs.inspect(obj))

    return self
end

function saveState()
    hs.settings.set("state", obj._state)
    hs.settings.set("soundIdx", obj._soundIdx)
    hs.settings.set("timeLeft", obj._timeLeft)
end

function obj:stop()
    saveState()
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
