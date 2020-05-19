local obj = {}

obj.name = "Lotus"
obj.version = "1.0"
obj.author = "Anthony D'Ambrosio <anthony.dayzerostudio@gmail.com>"
obj.homepage = "https://github.com/pancia/dotfiles/tree/master/spoons/lotus"
obj.license = "MIT - https://opensource.org/licenses/MIT"
obj.attributions = {
    "Lotus icon made by: https://www.flaticon.com/free-icon/lotus-flower_1152062",
    "gong.wav from: http://iamfutureproof.com/tools/awareness/",
    "bowl.wav from: http://naturesoundsfor.me/",
}

obj.spoonPath = hs.spoons.scriptPath()

obj.sounds = nil
obj.interval = { minutes = 30 }

function obj:playAwarenessSound()
    local sound = obj.sounds[obj._soundIdx]
    local volume = sound.volume or 1
    local s = sound.name
        and hs.sound.getByName(sound.name)
        or hs.sound.getByFile(obj.spoonPath.."/"..sound.path)
    obj.lastPlayedSound = s:volume(volume):play()
    hs.execute("mkdir -p "..obj.logDir)
    hs.execute("echo $(date +%T) -- '"..(sound.name or sound.path).."' >> "..obj.logDir.."/log")
    return self
end

function obj:stopAwarenessSound()
    if obj.lastPlayedSound then
        obj.lastPlayedSound:stop()
        obj.lastPlayedSound = nil
    end
    return self
end

function obj:init()
    obj._paused = false
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

function showDurationPicker(onDuration, onClose)
    local frame = hs.screen.primaryScreen():fullFrame()
    local rect = hs.geometry.rect(
    frame["x"] + (3 * frame["w"] / 8),
    frame["y"] + 3 * (frame["h"] / 8),
    2 * frame["w"] / 8,
    2 * frame["h"] / 8)
    local uc = hs.webview.usercontent.new("HammerSpoon") -- jsPortName
    local browser
    local pickedDuration = false
    uc:setCallback(function(response)
        local duration = response.body
        pickedDuration = true
        browser:delete()
        onDuration(duration)
    end)
    browser = hs.webview.newBrowser(rect, {developerExtrasEnabled = true}, uc)
    browser:windowCallback(function(action, webview)
        if action == "closing" and not pickedDuration then
            if onClose then onClose(duration) end
        end
    end)
    browser:deleteOnClose(true)
    local f = io.open(obj.spoonPath.."/durationPicker.html")
    local html = ""
    for each in f:lines() do
        html = html .. each
    end
    browser:html(html):bringToFront():show()
end

function restartTimer()
    obj.stopAwarenessSound()
    obj._lotusTimer = obj._lotusTimer:start()
    obj._menuRefreshTimer:fire()
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
                obj._lotusTimer = obj._lotusTimer:setNextTrigger(obj._lastNextTrigger)
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
                restartTimer()
            end},
        }
    else
        return {
            {title = "pause for ...?"
            , fn = function()
                obj.stopAwarenessSound()
                showDurationPicker(function(duration)
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
                end)
            end},
            {title = "view log"
            , fn = function()
                local logFileLoc = obj.logDir.."/log"
                hs.osascript.applescript("tell application \"iterm2\""
                .."\ncreate window with default profile command \"zsh -ic 'viewLog "..logFileLoc.."'\""
                .."\nend tell")
            end},
        }
    end
end

function with_default(obj, key, default)
    obj[key] = obj[key] or default
end

function snoozeTimer()
    showDurationPicker(function(duration)
        obj._paused = true
        obj._lotusTimer = obj._lotusTimer:stop()
        _, refreshRate = userIntervalToSeconds(obj.interval)
        obj._pauseTimer = hs.timer.doAfter(refreshRate*duration, function()
            obj._pauseTimer = nil
            restartTimer()
        end)
        obj._menuRefreshTimer:fire()
    end, function()
        obj._paused = false
        restartTimer()
    end)
end

function notifCallback(notif)
    local action = obj._sound.action
    local activationType = notif:activationType()
    if activationType == hs.notify.activationTypes.actionButtonClicked then
        snoozeTimer()
    else
        if action then
            action(function()
                obj._paused = false
                obj._soundIdx = (obj._soundIdx % #obj.sounds) + 1
                restartTimer()
            end)
        else
            obj._soundIdx = (obj._soundIdx % #obj.sounds) + 1
            restartTimer()
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
        obj._notif = hs.notify.new(notifCallback, notification):send()
        clearCheck = hs.timer.doEvery(1, function()
            if not hs.fnutils.contains(hs.notify.deliveredNotifications(), obj._notif) then
                if obj._notif:activationType() == hs.notify.activationTypes.none then
                    notifCallback(obj._notif)
                end
                clearCheck:stop()
                clearCheck = nil
            end
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

function obj:start()
    local saved = {
        ["soundIdx"] = hs.settings.get("soundIdx"),
        ["pausedFor"] = hs.settings.get("pausedFor"),
        ["nextTrigger"] = hs.settings.get("nextTrigger"),
    }
    hs.printf("Lotus started with: %s", hs.inspect(saved))
    obj._soundIdx = saved["soundIdx"] or #obj.sounds
    obj._menubar = hs.menubar.new():setMenu(renderMenu)

    interval, refreshRate = userIntervalToSeconds(obj.interval)
    if saved["pausedFor"] then
        obj._paused = true
        obj._lastNextTrigger = saved["nextTrigger"]
        obj._pauseTimer = hs.timer.doAfter(refreshRate*saved["pausedFor"], function()
            obj._pauseTimer = nil
            obj._paused = false
            obj._lotusTimer = hs.timer.doEvery(interval, lotusBlock)
            obj._lotusTimer = obj._lotusTimer:setNextTrigger(obj._lastNextTrigger)
            obj._menuRefreshTimer:fire()
        end)
    else
        obj._lotusTimer = hs.timer.doEvery(interval, lotusBlock)
        obj._lotusTimer:setNextTrigger(saved["nextTrigger"] or interval)
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
    obj._menuRefreshTimer:stop()
    obj._menubar:delete()
    return self
end

return obj
