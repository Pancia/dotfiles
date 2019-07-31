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

localInstall("Lotus", {
    config = {
        sounds = {{path = "gong.wav", volume = .5, alert = "Take a break!"},
                  {path = "bowl.wav"},
                  {path = "bowl.wav"}},
        triggerEvery = 20, -- minutes
        notifOptions = false,
    },
    start = true,
})

localInstall("Cmus", {
    config = {},
    start = true,
})

ytdl = function(requestType, path, headers, body)
    print("requestType: "..requestType)
    print("path: "..path)
    print("headers: "..hs.inspect(headers))

    assert(headers["Host"] == "localhost:5555", "expected 'Host' in headers to be 'localhost:5555'")
    assert(requestType == "POST", "expected a POST request")

    print(hs.inspect(body))

    dlDir = "~/Downloads/ytdl/"
    fmtString = "%(title)s__#__%(id)s.%(ext)s."
    cmd = "youtube-dl -o '"..dlDir..fmtString.."' -f 140 "..path:gsub("^/", "").." 2>&1"
    print("cmd: "..cmd)
    local output, status = hs.execute(cmd, true)
    print("status", status)
    print("output", output)

    return "ytdl: ok", 200, {["Access-Control-Allow-Origin"] = "https://www.youtube.com"}
end
hs.httpserver.new():setCallback(ytdl):setPort(5555):start()
