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

Install:andUse("FadeLogo", {
    config = {
        default_run = 1.0,
    },
    start = true
})

local function _x(cmd, errfmt, ...)
   local output, status = hs.execute(cmd)
   if status then
      return string.gsub(output, "\n*$", "")
   else
      print(string.format(errfmt, ...))
      return nil
   end
end

localRepo = "~/dotfiles/spoons/"
localInstall = function(name, conf)
    spoonDir = localRepo .. name
    if hs.fs.attributes(spoonDir) then
        outdir = hs.configdir.."/Spoons/"..name..".spoon"
        _x("rm -r "..outdir
        , "failed to clear '%s'", outdir)
        _x("mkdir -p "..outdir
        , "failed to make dir '%s'", outdir)
        _x("cp "..spoonDir.."/* "..outdir
        , "failed to copy '%s' local spoon to '%s'", spoonDir, outdir)
        hs.spoons.use(name, conf)
    end
end

local HOME = os.getenv("HOME")

function showHomeBoard(onClose, onResponse)
    local frame = hs.screen.primaryScreen():fullFrame()
    local rect = hs.geometry.rect(
    frame["x"] + 2 * (frame["w"] / 8),
    frame["y"] + 1 * (frame["h"] / 8),
    2 * frame["w"] / 4,
    3 * frame["h"] / 4)
    local uc = hs.webview.usercontent.new("HammerSpoon") -- jsPortName
    local browser
    local responded = false
    uc:setCallback(function(response)
        local body = response.body
        responded = true
        browser:delete()
        onResponse(body)
    end)
    browser = hs.webview.newBrowser(rect, {developerExtrasEnabled = true}, uc)
    browser:windowCallback(function(action, webview)
        if action == "closing" then
            onClose(duration)
        end
    end)
    browser:deleteOnClose(true)
    browser:transparent(true)
    local f = io.open(HOME.."/Dropbox/HomeBoard/index.html")
    local html = ""
    for each in f:lines() do
        html = html .. each
    end
    browser:html(html):bringToFront():show()
end

localInstall("Lotus", {
    start = true,
    config = {
        logDir = HOME.."/.log/lotus/",
        sounds = {
            {name = "short", path = "bowl.wav"
            , action = function(onDone)
                showHomeBoard(onDone, function(body)
                    local journal = hs.execute("printf '%s' `date +%y-%m-%d_%H:%M`")
                    io.open(HOME.."/Dropbox/HomeBoard/"..journal..".txt", "w")
                        :write(body)
                        :close()
                end)
            end, notif = {title = "Quick Stretch! #short", withdrawAfter = 0}},
            {name = "long", path = "gong.wav", volume = .5
            , notif = {title = "Take a break! #long", withdrawAfter = 0}},
            {name = "short", path = "bowl.wav"
            , notif = {title = "Quick Stretch! #short", withdrawAfter = 0}},
            {name = "reset", path = "gong.wav", volume = .5
            , notif = {title = "Take 10 to #review #plan", withdrawAfter = 0}},
        },
        interval = { minutes = 30 },
        notifOptions = false,
    },
})

localInstall("Cmus", {
    start = true,
    config = {},
})

localInstall("Watch", {
    start = true,
    config = {
        logDir = os.getenv("HOME").."/.log/watch/",
        scripts = {
            {name = "disable_osx_startup_chime"
            , command = "~/dotfiles/misc/watch/disable_osx_startup_chime.watch.sh"
            , triggerEvery = 60 -- every hour
            , delayStart = 0}, -- run immediately on start
            {name = "ytdl"
            , command = "~/dotfiles/misc/watch/ytdl/ytdl.watch.sh"
            , triggerEvery = 15 -- every 15 minutes
            , delayStart = 5}, -- delay 5 minutes from start
            {name = "extra"
            , command = "~/dotfiles/misc/watch/extra.watch.sh"
            , triggerEvery = 60 * 3 -- every 3rd hour
            , delayStart = 15}, -- delay 15 minutes from start
        }
    },
})

