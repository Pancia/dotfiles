local obj = {}

obj.name = "Lotus"
obj.version = "1.0"
obj.author = "Anthony D'Ambrosio <anthony.dayzerostudio@gmail.com>"
obj.homepage = "https://github.com/pancia/dotfiles/tree/master/spoons/lotus"
obj.license = "MIT - https://opensource.org/licenses/MIT"

local function script_path()
    local str = debug.getinfo(2, "S").source:sub(2)
    return str:match("(.*/)")
end
obj.spoonPath = script_path()

obj.sounds = nil
obj.interval = 60 -- seconds
obj.triggerEvery = 20 -- minutes
obj.notifOptions = nil

function obj:playAwarenessSound()
    soundName = obj.sounds[obj._soundIdx].name
    volume = obj.sounds[obj._soundIdx].volume or 1
    sound = hs.sound.getByName(soundName):volume(volume)
    obj._soundIdx = (obj._soundIdx % #obj.sounds) + 1
    obj._menubar:setTitle("lotus:" .. soundName)
    sound:play()
    return self
end

function obj:init()
    obj._soundIdx = 1
end

function renderMenu()
    return {
        {title = (obj._stopped and "start" or "stop")
        , fn = function()
            if obj._stopped then
                obj._lotusTimer:start():setNextTrigger(0)
            else
                obj._lotusTimer:stop()
                obj._menubar:setTitle("lotus:stopped")
            end
            obj._stopped = not obj._stopped
        end},
        {title = "pause for an hour"
        , checked = obj._paused
        , fn = function()
            if obj._paused then
                obj._pauseTimer:stop()
                obj._lotusTimer:start():setNextTrigger(0)
            else
                obj._lotusTimer:stop()
                obj._pauseTimer = hs.timer.doAfter(60*60, function()
                    obj._lotusTimer:start():setNextTrigger(0)
                end)
                obj._menubar:setTitle("lotus:paused")
            end
            obj._paused = not obj._paused
        end},
    }
end

function lotusBlock()
    obj._menubar:setTitle("lotus:" .. obj._timerCounter)
    if obj._timerCounter == 0 then
        obj:playAwarenessSound()
        if obj.notifOptions then
            hs.notify.new(nil, obj.notifOptions):send()
        end
    end
    obj._timerCounter = (obj._timerCounter - 1) % obj.triggerEvery
end

function obj:start()
    obj._timerCounter = obj.triggerEvery

    obj._stopped = false
    obj._paused = false
    obj._menubar = hs.menubar.new():setMenu(renderMenu)
    obj._menubar:setTitle("lotus:" .. obj._timerCounter)

    obj:playAwarenessSound()
    obj._lotusTimer = hs.timer.doEvery(obj.interval, lotusBlock)

    return self
end

function obj:stop()
    obj._lotusTimer:stop()
    obj._menubar:delete()
    return self
end

return obj
