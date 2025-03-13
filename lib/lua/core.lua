-- CONTEXT: [[~/dotfiles/wiki/HammerSpoon.wiki]]

local HOME = os.getenv("HOME")

local install = hs.loadSpoon("SpoonInstall")
install.use_syncinstall = true

install:andUse("ClipboardTool", {
  start = true,
  hotkeys = {
    toggle_clipboard = {{"cmd", "ctrl"}, "p"}
  },
  config = {
      display_max_length = 50
  }
})

install:andUse("FadeLogo", {
  start = true,
  config = {default_run = 1.0}
})

function engage(seed_path, config)
  local seed = require(seed_path)
  seed:start(config)
end

local monitor = engage("seeds.monitor", {})

local hermes = engage("seeds.hermes", {})

local cmus = engage("seeds.cmus", {})

local homeboard = engage("seeds.homeboard.init", {
    homeBoardPath = HOME.."/Dropbox/HomeBoard/",
    videosPath = HOME.."/Movies/HomeBoard"
})

function notif(title)
  return function()
    return {title = title, withdrawAfter = 0}
  end
end

if false then
  local lotus = engage("seeds.lotus.init", {
    sounds = {
      {
        name  = "short",
        path  = "bowl.wav",
        notif = notif("Change position! #short")
      },
      {
        name  = "short",
        path  = "bowl.wav",
        notif = notif("Change position! #short")
      },
      {
        name   = "long",
        path   = "gong.wav",
        volume = .5,
        notif  = notif("Do some squats! #long")
      }
    }
  })
end

local watch = engage("seeds.watch.init", {
  logDir = HOME .. "/.log/watch/",
  scripts = {
    {
      name = "disable_osx_startup_chime",
      command = HOME.."/dotfiles/misc/watch/disable_osx_startup_chime.watch.sh",
      triggerEvery = 60,
      delayStart = 0
    },
    {
      name = "ytdl",
      command = HOME.."/dotfiles/misc/watch/ytdl/ytdl.watch.sh",
      triggerEvery = 15,
      delayStart = 5
    },
    {
      name = "extra",
      command = HOME.."/dotfiles/misc/watch/extra.watch.sh",
      triggerEvery = 60 * 3,
      delayStart = 15
    }
  }
})

local seeds = {lotus = lotus, watch = watch, homeboard = homeboard, monitor = monitor}

local hs_global_modifier = {"cmd", "ctrl"}

hs.hotkey.bindSpec({hs_global_modifier, "c"}, hs.toggleConsole)

hs.hotkey.bindSpec({hs_global_modifier, "r"}, function()
  for name, seed in pairs(seeds) do
    if seed.stop then
      ok, err = pcall(function() seed.stop() end)
      if not ok then
        hs.printf("\n\nERROR: stop(%s):\n%s\n\n", name, errmsg)
      end
    end
  end
  hs.reload()
end)
