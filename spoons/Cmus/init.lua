local obj = {}

obj.name = "Cmus Media Controls"
obj.version = "1.0"
obj.author = "Anthony D'Ambrosio <anthony.dayzerostudio@gmail.com>"
obj.homepage = "https://github.com/pancia/dotfiles/tree/master/spoons/cmus"
obj.license = "MIT - https://opensource.org/licenses/MIT"

obj.cmusPath = "/usr/local/bin/"

function obj:init()
end

function cmusRemote(command)
	return hs.execute(obj.cmusPath.."/cmus-remote "..command)
end

function isActive()
    _, status = hs.execute(obj.cmusPath.."/cmus-remote --raw status")
    return status
end

function isPlaying()
    cmusStatus = hs.execute(obj.cmusPath.."/cmus-remote --raw status")
    return string.match(cmusStatus, "status playing")
end

function notify()
    res, status = cmusRemote("--raw status")
    if status then
        artist = string.match(res, "tag artist ([^\n]+)")
        album = string.match(res, "tag album ([^\n]+)")
        title = string.match(res, "tag title ([^\n]+)")
        hs.notify.show(title, artist, album)
    end
end

function obj:start()
    obj._hotkeys = {}
    table.insert(obj._hotkeys, hs.hotkey.bind({}, "f7", function()
        if isActive() then
            cmusRemote("--prev")
            notify()
        end
    end))
    table.insert(obj._hotkeys, hs.hotkey.bind("shift", "f7", function()
        if isActive() then
            cmusRemote("--seek -10")
        end
    end))
    table.insert(obj._hotkeys, hs.hotkey.bind({}, "f8", function()
        if isActive() then
            cmusRemote("--pause")
        end
    end))
    table.insert(obj._hotkeys, hs.hotkey.bind({}, "f9", function()
        if isActive() then
            cmusRemote("--next")
            notify()
        end
    end))
    table.insert(obj._hotkeys, hs.hotkey.bind("shift", "f9", function()
        if isActive() then
            cmusRemote("--seek +10")
        end
    end))
    table.insert(obj._hotkeys, hs.hotkey.bind({}, "f19", function()
        if isActive() and isPlaying() then
            cmusRemote("--volume -5")
        else
            output = hs.audiodevice.defaultOutputDevice()
            output:setVolume(output:volume() - 5)
            hs.sound.getByName("Pop"):play()
        end
    end))
    table.insert(obj._hotkeys, hs.hotkey.bind({}, "f20", function()
        if isActive() and isPlaying() then
            cmusRemote("--volume +5")
        else
            output = hs.audiodevice.defaultOutputDevice()
            output:setVolume(output:volume() + 5)
            hs.sound.getByName("Pop"):play()
        end
    end))
    table.insert(obj._hotkeys, hs.hotkey.bind("cmd", "f19", function()
        output = hs.audiodevice.defaultOutputDevice()
        output:setVolume(output:volume() - 5)
        hs.sound.getByName("Pop"):play()
    end))
    table.insert(obj._hotkeys, hs.hotkey.bind("cmd", "f20", function()
        output = hs.audiodevice.defaultOutputDevice()
        output:setVolume(output:volume() + 5)
        hs.sound.getByName("Pop"):play()
    end))
    return self
end

function obj:stop()
    hs.fnutils.each(obj._hotkeys, function(hotkey)
        hotkey:delete()
    end)
    return self
end

return obj
