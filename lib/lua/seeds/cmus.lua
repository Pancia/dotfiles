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

function obj:incVolume()
    if isActive() and isPlaying() then
        cmusRemote("--volume +5")
    end
end

function obj:decVolume()
    if isActive() and isPlaying() then
        cmusRemote("--volume -5")
    end
end

function obj:spotifyplayOrPause()
    hs.spotify.playpause()
end

function obj:spotifyprevTrack()
    hs.spotify.previous()
end

function obj:spotifynextTrack()
    hs.spotify.next()
end

function obj:spotifyincVolume()
    hs.spotify.volumeUp()
end

function obj:spotifydecVolume()
    hs.spotify.volumeDown()
end

function bindMediaKeys()
    hs.hotkey.bind({}, "f7",  obj.prevTrack)
    hs.hotkey.bind({}, "f8",  obj.playOrPause)
    hs.hotkey.bind({}, "f9",  obj.nextTrack)
    hs.hotkey.bind({}, "f13", obj.decVolume)
    hs.hotkey.bind({}, "f14", obj.incVolume)
    hs.hotkey.bind({"cmd"}, "f7",  obj.spotifyprevTrack)
    hs.hotkey.bind({"cmd"}, "f8",  obj.spotifyplayOrPause)
    hs.hotkey.bind({"cmd"}, "f9",  obj.spotifynextTrack)
    hs.hotkey.bind({"cmd"}, "f13", obj.spotifydecVolume)
    hs.hotkey.bind({"cmd"}, "f14", obj.spotifyincVolume)
    -- cmd+shift f7/8/9 are bound from karabiner.json
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

-- see bin/cmus-status-display
function obj:onIPCMessage(_id, msg)
    local title = ""
    if isPlaying() then
        title = string.format("🎵%23s ⏸", msg)
    elseif string.len(msg) == 0 then
        title = string.format("🎵nil▶️")
    else
        title = string.format("🎵%23s ▶️", msg)
    end
    local styledTitle = hs.styledtext.new(title, {["font"] = {["name"] = "Menlo-Regular"}})
    obj._controlsMenu:setTitle(styledTitle)
end

function obj:initMenuTitle()
    res, status = cmusRemote("--raw status")
    artist = ""; title = ""
    if status then
        artist = string.match(res, "tag artist ([^\n]+)")
        title = string.match(res, "tag title ([^\n]+)")
    end
    if title == "" then
        obj:onIPCMessage(0, "")
    else
        obj:onIPCMessage(0, string.format("%.10s - %.10s", artist, title))
    end
end

function openInITerm(command)
    local script = string.format([[
        tell application "iTerm"
            create window with default profile command "%s"
            activate
        end tell
    ]], command)
    hs.osascript.applescript(script)
end

function obj:createControlsCanvas()
    local buttonWidth = 100
    local buttonHeight = 40
    local padding = 8
    local rowHeight = buttonHeight + padding
    local canvasWidth = (buttonWidth * 3) + (padding * 4)
    local canvasHeight = (rowHeight * 5) + padding

    obj._canvas = hs.canvas.new({x = 0, y = 0, w = canvasWidth, h = canvasHeight})
    obj._canvas:level("popUpMenu")
    obj._canvas:behavior({"canJoinAllSpaces", "stationary"})

    -- Background
    obj._canvas:appendElements({
        type = "rectangle",
        action = "fill",
        fillColor = {hex = "#1e1e1e", alpha = 0.95},
        roundedRectRadii = {xRadius = 8, yRadius = 8},
    })

    -- Button configurations
    local buttons = {
        -- Row 1: Media controls (3 buttons @ 100px)
        {id = "prev", label = "⏮ Previous", x = padding, y = padding, w = buttonWidth},
        {id = "playpause", label = "⏯ Play/Pause", x = padding * 2 + buttonWidth, y = padding, w = buttonWidth},
        {id = "next", label = "⏭ Next", x = padding * 3 + buttonWidth * 2, y = padding, w = buttonWidth},

        -- Row 2: Seek controls (4 buttons @ 75px)
        {id = "seek_back_30", label = "⏪ 30s", x = padding, y = padding + rowHeight, w = 75},
        {id = "seek_back_10", label = "⏪ 10s", x = padding * 2 + 75, y = padding + rowHeight, w = 75},
        {id = "seek_fwd_10", label = "⏩ 10s", x = padding * 3 + 75 * 2, y = padding + rowHeight, w = 75},
        {id = "seek_fwd_30", label = "⏩ 30s", x = padding * 4 + 75 * 3, y = padding + rowHeight, w = 75},

        -- Row 3: Volume controls (2 buttons @ 155px, centered)
        {id = "vol_down", label = "🔉 Vol -", x = padding, y = padding + rowHeight * 2, w = 155},
        {id = "vol_up", label = "🔊 Vol +", x = padding * 2 + 155, y = padding + rowHeight * 2, w = 155},

        -- Row 4: Select controls (2 buttons @ 155px)
        {id = "select_playlist", label = "📋 Playlist", x = padding, y = padding + rowHeight * 3, w = 155},
        {id = "select_tags", label = "🏷 Tags", x = padding * 2 + 155, y = padding + rowHeight * 3, w = 155},

        -- Row 5: Edit controls (2 buttons @ 155px)
        {id = "edit_track", label = "✏️ Edit", x = padding, y = padding + rowHeight * 4, w = 155},
        {id = "audacity", label = "🎧 Audacity", x = padding * 2 + 155, y = padding + rowHeight * 4, w = 155},
    }

    for _, btn in ipairs(buttons) do
        -- Button background
        obj._canvas:appendElements({
            id = btn.id .. "_bg",
            type = "rectangle",
            action = "fill",
            fillColor = {hex = "#2d2d2d", alpha = 1},
            strokeColor = {hex = "#3d3d3d", alpha = 1},
            strokeWidth = 1,
            roundedRectRadii = {xRadius = 6, yRadius = 6},
            frame = {x = btn.x, y = btn.y, w = btn.w, h = buttonHeight},
            trackMouseEnterExit = true,
            trackMouseUp = true,
        })

        -- Button text
        obj._canvas:appendElements({
            id = btn.id .. "_text",
            type = "text",
            action = "fill",
            text = btn.label,
            textColor = {hex = "#ffffff", alpha = 1},
            textSize = 12,
            textAlignment = "center",
            frame = {x = btn.x, y = btn.y + buttonHeight/4, w = btn.w, h = buttonHeight},
            trackMouseEnterExit = true,
            trackMouseUp = true,
        })
    end

    -- Helper function to find element index by ID
    local function findElementIndexById(canvas, elementId)
        for i = 1, #canvas do
            if canvas[i].id == elementId then
                return i
            end
        end
        return nil
    end

    -- Mouse callback for interactions
    obj._canvas:mouseCallback(function(canvas, event, id, x, y)
        local btnId = string.gsub(id, "_bg", ""):gsub("_text", "")

        if event == "mouseEnter" and btnId ~= "_canvas_" then
            -- Highlight on hover
            local bgId = btnId .. "_bg"
            local idx = findElementIndexById(canvas, bgId)
            if idx then
                canvas[idx].fillColor = {hex = "#3d3d3d", alpha = 1}
            end
        elseif event == "mouseExit" and btnId ~= "_canvas_" then
            -- Remove highlight
            local bgId = btnId .. "_bg"
            local idx = findElementIndexById(canvas, bgId)
            if idx then
                canvas[idx].fillColor = {hex = "#2d2d2d", alpha = 1}
            end
        elseif event == "mouseUp" then
            -- Row 1: Media controls
            if btnId == "prev" then
                obj:prevTrack()
            elseif btnId == "playpause" then
                obj:playOrPause()
            elseif btnId == "next" then
                obj:nextTrack()
            -- Row 2: Seek controls
            elseif btnId == "seek_back_30" then
                obj:seekBackwards(30)()
            elseif btnId == "seek_back_10" then
                obj:seekBackwards(10)()
            elseif btnId == "seek_fwd_10" then
                obj:seekForwards(10)()
            elseif btnId == "seek_fwd_30" then
                obj:seekForwards(30)()
            -- Row 3: Volume controls
            elseif btnId == "vol_down" then
                obj:decVolume()
            elseif btnId == "vol_up" then
                obj:incVolume()
            -- Row 4: Select controls (open in iTerm)
            elseif btnId == "select_playlist" then
                obj:selectByPlaylist()
                obj:hideControlsCanvas()
            elseif btnId == "select_tags" then
                obj:selectByTags()
                obj:hideControlsCanvas()
            -- Row 5: Edit controls (open in iTerm)
            elseif btnId == "edit_track" then
                openInITerm("cmedit")
                obj:hideControlsCanvas()
            elseif btnId == "audacity" then
                openInITerm("cmaudacity")
                obj:hideControlsCanvas()
            elseif id == "_canvas_" then
                -- Clicked outside buttons, close popup
                obj:hideControlsCanvas()
            end
        end
    end)

    -- Enable canvas-level mouse events to detect clicks outside buttons
    obj._canvas:canvasMouseEvents(true, true, false, false)
end

function obj:showControlsCanvas()
    if not obj._canvas then
        obj:createControlsCanvas()
    end

    local menuFrame = obj._controlsMenu:frame()
    if menuFrame then
        -- Find which screen contains the menubar item
        local menuCenter = {x = menuFrame.x + menuFrame.w/2, y = menuFrame.y + menuFrame.h/2}
        local targetScreen = hs.screen.find(menuCenter)

        if targetScreen then
            -- Position canvas below the menubar item on the same screen
            obj._canvas:topLeft({x = menuFrame.x, y = menuFrame.y + menuFrame.h + 2})
        else
            -- Fallback to main screen if we can't determine the screen
            local mainScreen = hs.screen.mainScreen()
            local screenFrame = mainScreen:frame()
            obj._canvas:topLeft({x = screenFrame.x + (screenFrame.w - obj._canvas:frame().w)/2,
                                 y = screenFrame.y + 100})
        end

        obj._canvas:show(0.2)

        -- Watch for clicks outside canvas (using mouseUp to avoid interfering with button clicks)
        if obj._eventtap then obj._eventtap:stop() end
        obj._eventtap = hs.eventtap.new({hs.eventtap.event.types.leftMouseUp}, function(event)
            local mousePos = hs.mouse.absolutePosition()
            local canvasFrame = obj._canvas:frame()
            print(string.format("[DEBUG] mousePos: x=%.2f, y=%.2f", mousePos.x, mousePos.y))
            if canvasFrame then
                print(string.format("[DEBUG] canvasFrame: x=%.2f, y=%.2f, w=%.2f, h=%.2f", canvasFrame.x, canvasFrame.y, canvasFrame.w, canvasFrame.h))
                local isInside = hs.geometry.point(mousePos):inside(canvasFrame)
                print(string.format("[DEBUG] isInside: %s", tostring(isInside)))
                if not isInside then
                    print("[DEBUG] Closing canvas - click was outside")
                    obj:hideControlsCanvas()
                else
                    print("[DEBUG] Not closing - click was inside canvas")
                end
            else
                print("[DEBUG] canvasFrame is nil")
            end
        end):start()

        -- Watch for Escape key
        if obj._escapeWatcher then obj._escapeWatcher:stop() end
        obj._escapeWatcher = hs.eventtap.new({hs.eventtap.event.types.keyDown}, function(event)
            if event:getKeyCode() == 53 then -- Escape key
                obj:hideControlsCanvas()
                return true
            end
        end):start()
    end
end

function obj:hideControlsCanvas()
    if obj._canvas then
        obj._canvas:hide(0.1)
    end
    if obj._eventtap then
        obj._eventtap:stop()
        obj._eventtap = nil
    end
    if obj._escapeWatcher then
        obj._escapeWatcher:stop()
        obj._escapeWatcher = nil
    end
end

function obj:toggleControlsCanvas()
    if obj._canvas and obj._canvas:isShowing() then
        obj:hideControlsCanvas()
    else
        obj:showControlsCanvas()
    end
end

function obj:start(config)
    wake:onSleep(onSleep):start()
    bindMediaKeys()
    obj._ipcPort = hs.ipc.localPort("cmus", obj.onIPCMessage)
    obj._controlsMenu = hs.menubar.new()
    obj:initMenuTitle()
    obj._controlsMenu:setClickCallback(function()
        obj:toggleControlsCanvas()
    end)
end

return obj
