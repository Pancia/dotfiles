local obj = {}

obj.name = "Lotus"
obj.version = "1.0"
obj.author = "Anthony D'Ambrosio <anthony.dayzerostudio@gmail.com>"
obj.homepage = "https://github.com/pancia/dotfiles/tree/master/spoons/lotus"
obj.license = "MIT - https://opensource.org/licenses/MIT"
obj.attributions = "Lotus icon made by: https://www.flaticon.com/free-icon/lotus-flower_1152062"

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
    sound = obj.sounds[obj._soundIdx]
    volume = sound.volume or 1
    s = sound.name
        and hs.sound.getByName(sound.name)
        or hs.sound.getByFile(obj.spoonPath.."/"..sound.path)
    s:volume(volume):play()
    renderMenuBar(sound.name)
    obj._soundIdx = (obj._soundIdx % #obj.sounds) + 1
    return self
end

function obj:init()
    obj._soundIdx = 1
    obj._paused = false
end

function renderMenuBar(text)
    text = text or obj._timerCounter
    obj._menubar:setIcon(obj.spoonPath.."/lotus-flower.png")
    obj._menubar:setTitle(text)
end

function renderMenu()
    return {
        {title = (obj._paused and "resume" or "pause")
        , fn = function()
            if obj._paused then
                obj._lotusTimer:start()
                renderMenuBar()
            else
                obj._lotusTimer:stop()
                obj._pauseTimer:stop()
                renderMenuBar("||")
            end
            obj._paused = not obj._paused
        end},
        {title = "pause for an hour"
        , checked = obj._paused
        , fn = function()
            if obj._paused then
                obj._pauseTimer:stop()
                obj._lotusTimer:start()
                renderMenuBar()
            else
                obj._lotusTimer:stop()
                renderMenuBar("||1h")
                obj._pauseTimer = hs.timer.doAfter(60*60, function()
                    renderMenuBar()
                end)
            end
            obj._paused = not obj._paused
        end},
    }
end

function lotusBlock()
    renderMenuBar()
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
    obj._menubar = hs.menubar.new():setMenu(renderMenu)
    renderMenuBar()

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
