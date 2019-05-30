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

function obj:start()
    obj._timerCounter = obj.triggerEvery
    obj._menubar = hs.menubar.new()
    obj._menubar:setTitle("lotus:" .. obj._timerCounter)

    obj:playAwarenessSound()
    obj._timer = hs.timer.doEvery(obj.interval, function()
        obj._menubar:setTitle("lotus:" .. obj._timerCounter)

        if obj._timerCounter == 0 then
            obj:playAwarenessSound()
            if obj.notifOptions then
                hs.notify.new(nil, obj.notifOptions):send()
            end
        end

        obj._timerCounter = (obj._timerCounter - 1) % obj.triggerEvery
    end)

    return self
end

function obj:stop()
    obj._timer:stop()
    obj._menubar:delete()
    return self
end

return obj
