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

local function script_path()
    local str = debug.getinfo(2, "S").source:sub(2)
    return str:match("(.*/)")
end
obj.spoonPath = script_path()

obj.sounds = nil
obj.interval = { minutes = 30 }
obj.notifOptions = nil

function obj:playAwarenessSound()
    local sound = obj.sounds[obj._soundIdx]
    local volume = sound.volume or 1
    local s = sound.name
        and hs.sound.getByName(sound.name)
        or hs.sound.getByFile(obj.spoonPath.."/"..sound.path)
    obj.lastPlayedSound = s:volume(volume):play()
    obj._soundIdx = (obj._soundIdx % #obj.sounds) + 1
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
    obj._soundIdx = 1
    obj._paused = false
end

function renderMenuBar()
    local title
    if obj._paused then
        if obj._pauseTimer then
            title = "|| " .. math.ceil(obj._pauseTimer:nextTrigger() / 60)
        else
            title = "||"
        end
    else
        local sound = obj.sounds[obj._soundIdx]
        obj._menubar:setIcon(obj.spoonPath.."/lotus-flower.png")
        local soundTitle = sound.name or sound.path:match("[^/]+$"):match("[^.]+")
        local nextTrigger = obj._lotusTimer:nextTrigger()
        _, refreshRate = userIntervalToSeconds(obj.interval)
        title = math.max(math.ceil(nextTrigger / refreshRate), 0) .. "->" .. soundTitle
    end
    obj._menubar:setTitle(title)
end

function restartTimer()
    obj._lotusTimer = obj._lotusTimer:start()
end

function renderMenu()
    if obj._paused then
        return {
            {title = "restart"
            , fn = function()
                restartTimer()
                obj._paused = false
                obj._menuRefreshTimer:fire()
            end},
        }
    else
        return {
            {title = "pause"
            , fn = function()
                obj.stopAwarenessSound()
                obj._lotusTimer = obj._lotusTimer:stop()
                if obj._pauseTimer then
                    obj._pauseTimer:stop()
                    obj._pauseTimer = nil
                end
                obj._paused = true
                obj._menuRefreshTimer:fire()
            end},
            {title = "pause for >?"
            , fn = function()
                obj.stopAwarenessSound()
                obj._lotusTimer = obj._lotusTimer:stop()
                local frame = hs.screen.primaryScreen():fullFrame()
                local rect = hs.geometry.rect(
                    frame["x"] + (3 * frame["w"] / 8),
                    frame["y"] + 3 * (frame["h"] / 8),
                    2 * frame["w"] / 8,
                    2 * frame["h"] / 8)
                local uc = hs.webview.usercontent.new("durationPicker")
                local browser
                uc:setCallback(function(response)
                    local duration = response.body
                    browser:delete()
                    obj._pauseTimer = hs.timer.doAfter(60*duration, function()
                        obj._pauseTimer = nil
                        obj._lotusTimer = obj._lotusTimer:start()
                    end)
                    obj._menuRefreshTimer:fire()
                end)
                browser = hs.webview.newBrowser(rect, {developerExtrasEnabled = true}, uc)
                local f = io.open(obj.spoonPath.."/durationPicker.html")
                local html = ""
                for each in f:lines() do
                    html = html .. each
                end
                browser:html(html):bringToFront():show()
                obj._paused = true
                if obj._pauseTimer then
                    obj._pauseTimer:stop()
                    obj._pauseTimer = nil
                end
                obj._menuRefreshTimer:fire()
            end},
            {title = "restart"
            , fn = function()
                obj.stopAwarenessSound()
                obj._soundIdx = 1
                obj._lotusTimer:fire()
                obj._lotusTimer = obj._lotusTimer:stop()
                if obj._pauseTimer then
                    obj._pauseTimer:stop()
                    obj._pauseTimer = nil
                end
                restartTimer()
                obj._paused = false
                obj._menuRefreshTimer:fire()
            end},
            {title = "view log"
            , fn = function()
                local logFileLoc = obj.logDir.."/log"
                hs.execute("echo '"..logFileLoc.."' > $HOME/.init-zsh-cmds/viewLog", true)
                hs.execute("open -a Terminal $HOME", true)
            end},
        }
    end
end

function lotusBlock()
    local sound = obj.sounds[obj._soundIdx]
    obj:playAwarenessSound()
    if sound.notif then
        obj._lotusTimer = obj._lotusTimer:stop()
        obj._notif = hs.notify.new(restartTimer, sound.notif):send()
        clearCheck = hs.timer.doEvery(1, function()
            if not hs.fnutils.contains(hs.notify.deliveredNotifications(), obj._notif) then
                if obj._notif:activationType() == hs.notify.activationTypes.none then
                    restartTimer()
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
    obj._menubar = hs.menubar.new():setMenu(renderMenu)

    interval, refreshRate = userIntervalToSeconds(obj.interval)
    obj._lotusTimer = hs.timer.doEvery(interval, lotusBlock)
    obj:playAwarenessSound()

    renderMenuBar()
    obj._menuRefreshTimer = hs.timer.doEvery(refreshRate, renderMenuBar)

    return self
end

function obj:stop()
    if obj._pauseTimer then
        obj._pauseTimer:stop()
        obj._pauseTimer = nil
    end
    if obj._notif then
        obj._notif:withdraw()
    end
    obj._lotusTimer:stop()
    obj._menuRefreshTimer:stop()
    obj._menubar:delete()
    return self
end

return obj
