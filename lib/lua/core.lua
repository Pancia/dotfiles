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
  local success, result = pcall(function()
    local seed = require(seed_path)
    seed:start(config)
    return seed
  end)

  if not success then
    hs.notify.new({
      title = "Hammerspoon Seed Error",
      informativeText = string.format("Failed to load '%s': %s", seed_path, result),
      withdrawAfter = 10
    }):send()
    hs.printf("\n\n=== SEED ERROR: %s ===\n%s\n\n", seed_path, result)
    return nil
  end

  return result
end

local monitor = engage("seeds.monitor", {})

local cmus = engage("seeds.cmus", {})

local snippets = engage("seeds.snippets", {})

local calendar = engage("seeds.calendar.init", {
    -- Matches "#{anthony/autocal:focus}" and captures only "focus"
    tagPattern = "#%{anthony/autocal:([%w-_]+)%}",
    pollInterval = 60, -- Poll every 60 seconds
    queryWindow = 3, -- Look 3 hours ahead
    triggers = {
        tags = {
            ["focus"] = {
                leadMinutes = 5,
                action = function(event)
                    hs.notify.new(function(notification)
                        hs.alert.show("Focus time in 5 minutes!")
                    end,
                    {
                        title = "Focus Time Starting Soon",
                        informativeText = event.title,
                        withdrawAfter = 0,
                        hasActionButton = true,
                        actionButtonTitle = "Dismiss"
                    }):send()
                end
            },
        },
        titles = {
            ["Productivity & Accountability with Damian"] = {
                leadMinutes = 15,
                action = function(event)
                    hs.notify.new(function(notification)
                        hs.alert.show("SYMPOSIUM time in ~15 minutes!")
                    end,
                    {
                        title = "SYMPOSIUM Starting Soon",
                        informativeText = event.title,
                        withdrawAfter = 0,
                        hasActionButton = true,
                        actionButtonTitle = "Dismiss"
                    }):send()
                end
            },
        }
    }
})

function notif(title)
  return function()
    return {title = title, withdrawAfter = 0}
  end
end

local lotus = engage("seeds.lotus.init", {
    --interval = { minutes = 20 },
    clockTriggers = {
        [0] = 1,
        [30] = 2,
    },
    sounds = {
        {
            name  = "short",
            path  = "bowl.wav",
            notif = notif("Ohm... #short")
        },
        {
            name   = "long",
            path   = "gong.wav",
            volume = .5,
            notif  = notif("Ohm! #long")
        }
    }
})

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

local sanctuary = engage("seeds.sanctuary", {})

local function is_reloading()
  local reload_flag = "/tmp/hs_reloading"
  local file = io.open(reload_flag, "r")
  if file then
    file:close()
    os.remove(reload_flag)
    return true
  end
  return false
end

seeds = {}
if lotus then seeds.lotus = lotus end
if watch then seeds.watch = watch end
if monitor then seeds.monitor = monitor end
if snippets then seeds.snippets = snippets end
if calendar then seeds.calendar = calendar end
if sanctuary then seeds.sanctuary = sanctuary end

local hs_global_modifier = {"cmd", "ctrl"}

hs.hotkey.bindSpec({hs_global_modifier, "c"}, hs.toggleConsole)

hs.hotkey.bindSpec({hs_global_modifier, "r"}, function()
  local reload_flag = "/tmp/hs_reloading"
  local file = io.open(reload_flag, "w")
  if file then
    file:write("true")
    file:close()
  end

  hs.alert.show("⟳ Reloading...", 1)

  for name, seed in pairs(seeds) do
    if seed.stop then
      ok, err = pcall(function() seed.stop() end)
      if not ok then
        hs.printf("\n\nERROR: stop(%s):\n%s\n\n", name, errmsg)
      end
    end
  end

  hs.timer.doAfter(0.3, function()
    hs.reload()
  end)
end)

-- Show reload complete notification
if is_reloading() then
  hs.alert.show("✓ Hammerspoon reloaded", 1.5)
end

function myNotify(path)
    hs.notify.new(function(note)
        hs.task.new(path, nil):start()
    end, {
        title = 'title',
        informativeText = 'Click me!',
        withdrawAfter = 0
    }):send()
end

-- Sanctuary notification - opens VPC when clicked
local sanctuaryNotification = nil

function sanctuaryNotify()
    -- Withdraw any existing notification first
    if sanctuaryNotification then
        sanctuaryNotification:withdraw()
        sanctuaryNotification = nil
    end

    sanctuaryNotification = hs.notify.new(function(notification)
        sanctuaryNotification = nil
        hs.task.new("/usr/bin/open", nil, {"/Users/anthony/dotfiles/vpc/sanctuary.vpc"}):start()
    end, {
        title = "Sanctuary",
        informativeText = "Kitty is not running. Click to open workspace.",
        withdrawAfter = 0,
        hasActionButton = true,
        actionButtonTitle = "Open VPC",
        soundName = "default"
    })
    sanctuaryNotification:send()
end

-- Pymodoro notification with continuous sound until dismissed
local pomodoroSound = nil
local pomodoroSoundTimer = nil

function pomodoroNotify(title, message, soundPath)
    -- Stop any existing sound/timer
    if pomodoroSoundTimer then
        pomodoroSoundTimer:stop()
        pomodoroSoundTimer = nil
    end
    if pomodoroSound then
        pomodoroSound:stop()
        pomodoroSound = nil
    end

    -- Default sound if not specified
    soundPath = soundPath or "/System/Library/Sounds/Glass.aiff"

    -- Load and play sound
    pomodoroSound = hs.sound.getByFile(soundPath)
    if pomodoroSound then
        pomodoroSound:play()
        -- Set up timer to loop the sound
        pomodoroSoundTimer = hs.timer.doEvery(pomodoroSound:duration() + 0.5, function()
            if pomodoroSound then
                pomodoroSound:play()
            end
        end)
    end

    -- Create notification with callback
    hs.notify.new(function(notification)
        -- Stop sound when notification is clicked or dismissed
        if pomodoroSoundTimer then
            pomodoroSoundTimer:stop()
            pomodoroSoundTimer = nil
        end
        if pomodoroSound then
            pomodoroSound:stop()
            pomodoroSound = nil
        end
        -- Activate Kitty
        hs.application.launchOrFocus("kitty")
    end, {
        title = title or "Pymodoro",
        informativeText = message or "",
        withdrawAfter = 0,
        hasActionButton = true,
        actionButtonTitle = "Go to Kitty"
    }):send()
end
