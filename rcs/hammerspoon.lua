--<[.hammerspoon/init.lua]>

-- TODO: [[../wiki/HammerSpoon.wiki]]

hs_global_modifier = {"cmd", "ctrl"}
hs.hotkey.bindSpec({hs_global_modifier, "c"}, hs.toggleConsole)

hs.loadSpoon("SpoonInstall")
spoon.SpoonInstall.use_syncinstall = true
Install=spoon.SpoonInstall

-- ie: <cmd-ctrl-r>
Install:andUse("ReloadConfiguration", {
    hotkeys = {
        reloadConfiguration = {hs_global_modifier, "r"}
    }
})

Install:andUse("TextClipboardHistory", {
    -- config = { show_in_menubar = false, },
    hotkeys = {
        toggle_clipboard = {hs_global_modifier, "p"}
    }, start = true,
})

openWifiWiki = function(file)
    local frame = hs.screen.primaryScreen():fullFrame()
    rect = hs.geometry.rect(
    frame["x"] + (frame["w"] / 3),
    frame["y"] + (frame["h"] / 4),
    frame["w"] / 3,
    frame["h"] / 2)
    url = "file://"..file
    hs.webview.newBrowser(rect):url(url):show()
end

Install:andUse("WiFiTransitions", {
    config = {
        actions = {
            {
                doc = "Show ~/Dropbox/wiki/{ssid}.wiki if it exists",
                fn = function(_,_,_,ssid)
                    wiki = "/Users/Anthony/Dropbox/wiki/"..ssid..".html"
                    if hs.fs.attributes(wiki) ~= nil then
                        hs.notify.new(hs.fnutils.partial(openWifiWiki, wiki), {
                            title="View: "..ssid..".wiki"
                        }):send()
                    end
                end
            }
        },
    },
    start = true,
})

Install:andUse("Seal", {
    hotkeys = {show = {hs_global_modifier, "space"}},
    fn = function(s)
        s:loadPlugins({"apps", "calc", "screencapture", "useractions"})
        s.plugins.useractions.actions = {
            ["Hammerspoon docs webpage"] = {
                url = "http://hammerspoon.org/docs/",
                icon = hs.image.imageFromName(hs.image.systemImageNames.ApplicationIcon),
            },
        }
        s:refreshAllCommands()
    end,
    start = true,
})

Install:andUse("FadeLogo", {
    config = {
        default_run = 1.0,
    },
    start = true
})

lotus = function(sounds, options)
    c = 1
    getAwarenessSound = function()
        soundName = sounds[c][1]
        volume = sounds[c][2] or 1
        sound =  hs.sound.getByName(soundName):volume(volume)
        c = (c % #sounds) + 1
        return sound
    end

    counter = options.triggerEvery
    menubar = hs.menubar.new()
    menubar:setTitle("lotus:" .. counter)
    getAwarenessSound():play()
    interval = options.interval or 60
    timer = hs.timer.doEvery(interval, function()
        menubar:setTitle("lotus:" .. counter)

        if counter == 0 then
            getAwarenessSound():play()
            if options.notifOptions then
                hs.notify.new(nil, options.notifOptions):send()
            end
        end

        counter = (counter - 1) % interval
    end)
end

sounds = {{"gong",.5},
          {"bowl",1},
          {"bowl",1}}
lotus(sounds, {
    triggerEvery = 20, -- minutes
    notifOptions = false,
})
