-- CONTEXT: [[~/dotfiles/wiki/HammerSpoon.wiki]]

hs_global_modifier = {"cmd", "ctrl"}
hs.hotkey.bindSpec({hs_global_modifier, "c"}, hs.toggleConsole)

hs.loadSpoon("SpoonInstall")
spoon.SpoonInstall.use_syncinstall = true
Install=spoon.SpoonInstall

Install:andUse("TextClipboardHistory", {
    hotkeys = {
        toggle_clipboard = {hs_global_modifier, "p"}
    }, start = true,
})

Install:andUse("FadeLogo", {
    config = {
        default_run = 1.0,
    },
    start = true
})

function tryCatch(try, catch)
    local status, err = pcall(try)
    if not status then catch(err) end
end

-- ie: <cmd-ctrl-r>
local localSpoons = {}
hs.hotkey.bind(hs_global_modifier, "R", function()
    hs.fnutils.each(localSpoons, function(spoon)
        tryCatch(function()
            if spoon.stop then spoon.stop() end
        end, function(err)
            hs.printf("\n\n\nERROR: stop(%s):\n%s\n\n", spoon.name, err)
        end)
    end)
    hs.reload()
end)

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
        prevFn = conf["fn"]
        conf["fn"] = function(spoon)
            localSpoons[name] = spoon
            if prevFn then
                prevFn(spoon)
            end
        end
        hs.spoons.use(name, conf)
    end
end

local HOME = os.getenv("HOME")

local HomeBoard = nil
localInstall("HomeBoard", {
    start = true,
    config = {
        homeBoardPath = HOME.."/Dropbox/HomeBoard/",
        videosPath = HOME.."/Movies/HomeBoard",
        todosPaths = {
            dotfiles = HOME.."/dotfiles/wiki/TODO.wiki",
            dropbox  = HOME.."/Dropbox/wiki/Tasks.wiki"
        }
    },
    fn = function(spoon)
        HomeBoard = spoon
    end
})

localInstall("Lotus", {
    start = true,
    config = {
        logDir = HOME.."/.log/lotus/",
        sounds = {
            {name = "short", path = "bowl.wav"
            , notif = function() return {
                title = "Quick Stretch! #short", withdrawAfter = 0
                , informativeText = HomeBoard:getLastPlan()
                , subTitle = HomeBoard:getLastPlanTime()
            } end},
            {name = "long", path = "gong.wav", volume = .5
            , notif = function() return {
                title = "Take a walk! #long", withdrawAfter = 0
                , informativeText = HomeBoard:getLastPlan()
                , subTitle = HomeBoard:getLastPlanTime()
            } end},
            {name = "short", path = "bowl.wav"
            , notif = function() return {
                title = "Quick Stretch! #short", withdrawAfter = 0
                , informativeText = HomeBoard:getLastPlan()
                , subTitle = HomeBoard:getLastPlanTime()
            } end},
            {name = "long", path = "gong.wav", volume = .5
            , notif = function() return {
                title = "Take a walk! #long", withdrawAfter = 0
                , informativeText = HomeBoard:getLastPlan()
                , subTitle = HomeBoard:getLastPlanTime()
            } end},
            {name = "short", path = "bowl.wav"
            , notif = function() return {
                title = "Quick Stretch! #short", withdrawAfter = 0
                , informativeText = HomeBoard:getLastPlan()
                , subTitle = HomeBoard:getLastPlanTime()
            } end},
            {name = "reset", path = "gong.wav", volume = .5
            , action = function(onDone) HomeBoard:showHomeBoard(onDone) end
            , notif = function() return {
                title = "Take 10 to #review #plan", withdrawAfter = 0
                , informativeText = HomeBoard:getLastPlan()
                , subTitle = HomeBoard:getLastPlanTime()
            } end},
        },
        interval = { minutes = 30 },
    },
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

local LIB = "/Users/pancia/dotfiles/lib/fennel/"
fennel = require("fennel")
fennel.path = LIB.."/?.fnl;"..LIB.."/spacehammer/?.fnl;".. fennel.path
table.insert(package.loaders or package.searchers, fennel.searcher)
require("core")
