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

function showWakeDialog()
    local frame = hs.screen.primaryScreen():fullFrame()
    local x = (frame["w"] / 2) - 50
    local y = (frame["h"] / 2) - 50
    hs.dialog.alert(1, 1
        , function() callAll(obj.wakeCBs) end
        , "Wake up HammerSpoon?")
end

function watchSystem(eventType)
    if eventType == hs.caffeinate.watcher.systemWillSleep then
        callAll(obj.sleepCBs)
        showWakeDialog()
    end
end

function obj:start()
    if not obj._systemWatcher then
        obj._systemWatcher = hs.caffeinate.watcher.new(watchSystem):start()
    end
end

return obj
