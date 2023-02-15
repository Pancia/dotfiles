local obj = {}

local cmusRemotePath = hs.execute("which cmus-remote", true):gsub("%s+$", "")

function cmusRemote(action)
    return hs.execute(cmusRemotePath.." "..action)
end

function isActive()
    _, status = cmusRemote("--raw status")
    return status
end

function isPlaying()
    status = cmusRemote("--raw status")
    return string.match(status, "status playing")
end

function obj:playOrPause()
    if isActive() then
        -- NOTE: --pause toggles play/pause
        cmusRemote("--pause")
    end
end

function obj:prevTrack()
    if isActive() then
        cmusRemote("--prev")
    end
end

function obj:nextTrack()
    if isActive() then
        cmusRemote("--next")
    end
end

function obj:seekForwards(num)
    return function()
        cmusRemote("--seek +"..num)
    end
end

function obj:seekBackwards(num)
    return function()
        cmusRemote("--seek -"..num)
    end
end

function updateOSXVolume(num)
    local output = hs.audiodevice.defaultOutputDevice()
    output:setVolume(output:volume() + num)
    hs.sound.getByName("Pop"):play()
    hs.eventtap.event.newSystemKeyEvent("MUTE", true):post()
    hs.eventtap.event.newSystemKeyEvent("MUTE", false):post()
    hs.eventtap.event.newSystemKeyEvent("MUTE", true):post()
    hs.eventtap.event.newSystemKeyEvent("MUTE", false):post()
end

function obj:incOSXVolume()
    updateOSXVolume(100 / 15)
end

function obj:decOSXVolume()
    updateOSXVolume(-100 / 15)
end

function obj:incVolume()
    if isActive() and isPlaying() then
        cmusRemote("--volume +5")
    else
        obj:incOSXVolume()
    end
end

function obj:decVolume()
    if isActive() and isPlaying() then
        cmusRemote("--volume -5")
    else
        obj:decOSXVolume()
    end
end

function bindMediaKeys()
  hs.hotkey.bind({}, "f7", obj.prevTrack)
  hs.hotkey.bind({}, "f8", obj.playOrPause)
  hs.hotkey.bind({}, "f9", obj.nextTrack)
  hs.hotkey.bind({}, "f13", obj.decVolume)
  hs.hotkey.bind({}, "f14", obj.incVolume)
  hs.hotkey.bind("cmd", "f13", obj.decOSXVolume)
  hs.hotkey.bind("cmd", "f14", obj.incOSXVolume)
end

function obj:editTrack()
    if isActive() then
        hs.execute("cmedit", true)
    end
end

function obj:openInAudacity()
    if isActive() then
        hs.execute("cmaudacity", true)
    end
end

function obj:ytdlTrack()
    if isActive() then
        hs.execute("cmytdl", true)
    end
end

function obj:selectByPlaylist()
    if isActive() then
        hs.execute("cmselect", true)
    end
end

function obj:selectByTags()
    if isActive() then
        hs.execute("cmselect --filter-by-tags", true)
    end
end

local wake = require("lib/wakeDialog")

function onSleep()
    if isPlaying() then
        playOrPause()
    end
end

function obj:onIPCMessage(_id, msg)
  local title = ""
    if isPlaying() then
        title = string.format("🎵%43s ⏸", msg)
    else
        title = string.format("🎵%43s ▶️", msg)
    end
    local styledTitle = hs.styledtext.new(title, {["font"] = {["name"] = "Menlo-Regular"}})
    obj._playPauseMenu:setTitle(styledTitle)
end

function obj:initMenuTitle()
    res, status = cmusRemote("--raw status")
    artist = ""; title = ""
    if status then
        artist = string.match(res, "tag artist ([^\n]+)")
        title = string.match(res, "tag title ([^\n]+)")
    end
    obj:onIPCMessage(0, string.format("%.20s - %.20s", artist, title))
end

function obj:start(config)
    wake:onSleep(onSleep):start()
    bindMediaKeys()
    obj._ipcPort = hs.ipc.localPort("cmus", obj.onIPCMessage)
    obj._nextMenu = hs.menubar.new()
    obj._nextMenu:setTitle("⏭")
    obj._nextMenu:setClickCallback(obj.nextTrack)
    obj._playPauseMenu = hs.menubar.new()
    obj:initMenuTitle()
    obj._playPauseMenu:setClickCallback(obj.playOrPause)
    obj._prevMenu = hs.menubar.new()
    obj._prevMenu:setTitle("⏮")
    obj._prevMenu:setClickCallback(obj.prevTrack)
end

return obj
