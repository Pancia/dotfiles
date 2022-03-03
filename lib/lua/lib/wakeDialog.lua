local obj = {sleepCBs = {}, wakeCBs = {}}

function obj:onSleep(cb)
    table.insert(obj.sleepCBs, cb)
    return obj
end

function obj:onWake(cb)
    table.insert(obj.wakeCBs, cb)
    return obj
end

function callAll(cbs)
    hs.fnutils.each(cbs, function(cb) cb() end)
end

function obj:showWakeNotif()
    notification = {title = "Wake up hammerspoon?", withdrawAfter = 0 }
    if obj._notif then
        obj._notif:withdraw()
        obj._notif = nil
    end
    obj._notif = hs.notify.new(nil, notification):send()
    clearCheck = hs.timer.doEvery(3, function()
        if not hs.fnutils.contains(hs.notify.deliveredNotifications(), obj._notif) then
            if obj._notif and obj._notif:activationType() == hs.notify.activationTypes.none then
                callAll(obj.wakeCBs)
            end
            if clearCheck then
                clearCheck:stop()
                clearCheck = nil
            end
            obj._notif = nil
        end
    end)
end

function watchSystem(eventType)
    if eventType == hs.caffeinate.watcher.systemWillSleep then
        callAll(obj.sleepCBs)
        obj:showWakeNotif()
    end
end

function obj:start()
    if not obj._systemWatcher then
        -- FIXME obj._systemWatcher = hs.caffeinate.watcher.new(watchSystem):start()
    end
end

return obj
