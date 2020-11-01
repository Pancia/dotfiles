local durp = require("lib/durationpicker")

local obj = {}

obj.spoonPath = os.getenv("HOME").."/dotfiles/lib/fennel/seeds/lotus/"

obj.interval = { minutes = 30 }

function obj:playAwarenessSound()
    local sound = obj.sounds[obj._soundIdx]
    local volume = sound.volume or 1
    local s = sound.name
        and hs.sound.getByName(sound.name)
        or hs.sound.getByFile(obj.spoonPath.."/"..sound.path)
    obj.lastPlayedSound = s:volume(volume):play()
    return self
end

function obj:stopAwarenessSound()
    if obj.lastPlayedSound then
        obj.lastPlayedSound:stop()
        obj.lastPlayedSound = nil
    end
    return self
end

function renderMenuBar()
    local title
    local _, refreshRate = userIntervalToSeconds(obj.interval)
    if obj._paused then
        if obj._pauseTimer then
            local nextTrigger = obj._pauseTimer:nextTrigger()
            title = "|| " .. math.max(math.ceil(nextTrigger / refreshRate), 0)
        else
            title = "||"
        end
    else
        local sound = obj.sounds[obj._soundIdx]
        obj._menubar:setIcon(obj.spoonPath.."/lotus-flower.png")
        local soundTitle = sound.name or sound.path:match("[^/]+$"):match("[^.]+")
        local nextTrigger = obj._lotusTimer:nextTrigger()
        title = math.max(math.ceil(nextTrigger / refreshRate), 0)
            .. "->[" .. obj._soundIdx .. "/" .. #obj.sounds .."]#" .. soundTitle
    end
    obj._menubar:setTitle(title)
end

function renderMenu()
    if obj._paused then
        return {
            {title = "resume"
            , fn = function()
                obj._paused = false
                obj._lotusTimer:fire()
                if obj._pauseTimer then
                    obj._pauseTimer:stop()
                    obj._pauseTimer = nil
                end
                obj.stopAwarenessSound()
                obj._lotusTimer = obj._lotusTimer:setNextTrigger(obj._lastNextTrigger or 0)
                obj._menuRefreshTimer:fire()
            end},
            {title = "restart"
            , fn = function()
                obj._paused = false
                obj._soundIdx = 1
                obj._lotusTimer:fire()
                if obj._pauseTimer then
                    obj._pauseTimer:stop()
                    obj._pauseTimer = nil
                end
                obj.stopAwarenessSound()
                obj._lotusTimer = obj._lotusTimer:start()
                obj._menuRefreshTimer:fire()
            end},
        }
    else
        return {
            {title = "pause for ...?"
            , fn = function()
                obj.stopAwarenessSound()
                durp:show({
                    onDuration = function(duration)
                        obj._paused = true
                        if obj._pauseTimer then
                            obj._pauseTimer:stop()
                            obj._pauseTimer = nil
                        end
                        obj._menuRefreshTimer:fire()
                        obj._lastNextTrigger = obj._lotusTimer:nextTrigger()
                        obj._lotusTimer = obj._lotusTimer:stop()
                        _, refreshRate = userIntervalToSeconds(obj.interval)
                        obj._pauseTimer = hs.timer.doAfter(refreshRate*duration, function()
                            obj._pauseTimer = nil
                            obj._paused = false
                            obj._menuRefreshTimer:fire()
                            obj._lotusTimer = obj._lotusTimer:setNextTrigger(obj._lastNextTrigger)
                        end)
                        obj._menuRefreshTimer:fire()
                    end
                })
            end},
        }
    end
end

function with_default(obj, key, default)
    obj[key] = obj[key] or default
end

function snoozeTimer()
    durp:show({
        onDuration = function(duration)
            obj._paused = true
            obj.stopAwarenessSound()
            obj._lotusTimer = obj._lotusTimer:stop()
            _, refreshRate = userIntervalToSeconds(obj.interval)
            obj._pauseTimer = hs.timer.doAfter(refreshRate*duration, function()
                obj._pauseTimer = nil
                obj._paused = false
                obj._menuRefreshTimer:fire()
                obj._lotusTimer = obj._lotusTimer:setNextTrigger(0)
            end)
            obj._menuRefreshTimer:fire()
        end,
        onClose = function()
            obj._paused = false
            obj.stopAwarenessSound()
            obj._lotusTimer = obj._lotusTimer:start()
            obj._menuRefreshTimer:fire()
        end
    })
end

function obj:notifCallback()
    if obj._soundRepeat then
      obj._soundRepeat:stop()
      obj._soundRepeat = nil
    end
    local action = obj._sound.action
    local activationType = obj._notif:activationType()
    if activationType == hs.notify.activationTypes.actionButtonClicked then
        snoozeTimer()
    else
        local resume = function()
            obj._paused = false
            obj._soundIdx = (obj._soundIdx % #obj.sounds) + 1
            obj.stopAwarenessSound()
            obj._lotusTimer = obj._lotusTimer:start()
            obj._menuRefreshTimer:fire()
        end
        if action then
            action(resume)
        else
            resume()
        end
    end
end

function lotusBlock()
    obj._sound = obj.sounds[obj._soundIdx]
    obj:playAwarenessSound()
    if obj._sound.notif then
        obj._lotusTimer = obj._lotusTimer:stop()
        local notification = obj._sound.notif()
        with_default(notification, "hasActionButton", true)
        with_default(notification, "actionButtonTitle", "SNOOZE")
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
        obj._soundRepeat = hs.timer.doEvery(60, function()
          obj:playAwarenessSound()
        end)
    end
end

function userIntervalToSeconds(x)
    if x.minutes then
        return x.minutes * 60, 60
    else
        return x.seconds, 1
    end
end

function obj:start(config)
    for k,v in pairs(config) do obj[k] = v end
    local saved = {
        ["soundIdx"] = hs.settings.get("soundIdx"),
        ["pausedFor"] = hs.settings.get("pausedFor"),
        ["nextTrigger"] = hs.settings.get("nextTrigger"),
    }
    hs.printf("Lotus started with: %s", hs.inspect(saved))
    obj._soundIdx = saved["soundIdx"] or #obj.sounds
    obj._menubar = hs.menubar.new():setMenu(renderMenu)

    interval, refreshRate = userIntervalToSeconds(obj.interval)
    obj._lotusTimer = hs.timer.doEvery(interval, lotusBlock)

    if saved["pausedFor"] then
        obj._paused = true
        obj._lotusTimer = obj._lotusTimer:stop()
        obj._lastNextTrigger = saved["nextTrigger"]
        obj._pauseTimer = hs.timer.doAfter(saved["pausedFor"], function()
            obj._pauseTimer = nil
            obj._paused = false
            obj._lotusTimer = hs.timer.doEvery(interval, lotusBlock)
            obj._lotusTimer = obj._lotusTimer:setNextTrigger(obj._lastNextTrigger)
            obj._menuRefreshTimer:fire()
        end)
    else
        obj._lotusTimer:setNextTrigger((saved["nextTrigger"] < interval) and saved["nextTrigger"] or interval)
    end

    if not saved["soundIdx"] then
        obj:playAwarenessSound()
    end

    renderMenuBar()
    obj._menuRefreshTimer = hs.timer.doEvery(refreshRate, renderMenuBar)

    return self
end

function saveState()
    hs.settings.set("soundIdx", obj._soundIdx)
    if obj._paused then
        hs.settings.set("pausedFor", obj._pauseTimer:nextTrigger())
        hs.settings.set("nextTrigger", obj._lastNextTrigger)
    else
        hs.settings.set("pausedFor", nil)
        hs.settings.set("nextTrigger", obj._lotusTimer:nextTrigger())
    end
end

function obj:stop()
    saveState()
    if obj._pauseTimer then
        obj._pauseTimer:stop()
        obj._pauseTimer = nil
    end
    if obj._notif then
        obj._notif:withdraw()
    end
    if obj._lotusTimer then
        obj._lotusTimer:stop()
    end
    if obj._menuRefreshTimer then
      obj._menuRefreshTimer:stop()
    end
    if obj._menubar then
      obj._menubar:delete()
    end
    return self
end

return obj
