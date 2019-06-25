local obj = {}

obj.name = "Cmus Media Controls"
obj.version = "1.0"
obj.author = "Anthony D'Ambrosio <anthony.dayzerostudio@gmail.com>"
obj.homepage = "https://github.com/pancia/dotfiles/tree/master/spoons/cmus"
obj.license = "MIT - https://opensource.org/licenses/MIT"

function obj:init()
end

function cmusRemote(command)
    return hs.execute("cmus-remote "..command, true)
end

function isActive()
    _, status = hs.execute("cmus-remote --raw status", true)
    return status
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
    obj._prev = hs.hotkey.bind({}, "f7", function()
        if isActive() then
            cmusRemote("--prev")
            notify()
        end
    end)
    obj._seekBack = hs.hotkey.bind("shift", "f7", function()
        if isActive() then
            cmusRemote("--seek -10")
        end
    end)
    obj._pause = hs.hotkey.bind({}, "f8", function()
        if isActive() then
            cmusRemote("--pause")
        end
    end)
    obj._next = hs.hotkey.bind({}, "f9", function()
        if isActive() then
            cmusRemote("--next")
            notify()
        end
    end)
    obj._seekNext = hs.hotkey.bind("shift", "f9", function()
        if isActive() then
            cmusRemote("--seek +10")
        end
    end)
    obj._volumeDown = hs.hotkey.bind({}, "f19", function()
        if isActive() then
            cmusRemote("--volume -10")
        else
            output = hs.audiodevice.defaultOutputDevice()
            output:setVolume(output:volume() - 10)
        end
    end)
    obj._volumeUp = hs.hotkey.bind({}, "f20", function()
        if isActive() then
            cmusRemote("--volume +10")
        else
            output = hs.audiodevice.defaultOutputDevice()
            output:setVolume(output:volume() + 10)
        end
    end)
    obj._osxVolumeDown = hs.hotkey.bind("cmd", "f19", function()
        output = hs.audiodevice.defaultOutputDevice()
        output:setVolume(output:volume() - 5)
    end)
    obj._osxVolumeUp = hs.hotkey.bind("cmd", "f20", function()
        output = hs.audiodevice.defaultOutputDevice()
        output:setVolume(output:volume() + 5)
    end)
    return self
end

function obj:stop()
    obj._prev:delete()
    obj._prevSeek:delete()
    obj._pause:delete()
    obj._next:delete()
    obj._seekNext:delete()
    obj._volumeDown:delete()
    obj._volumeUp:delete()
    return self
end

return obj
