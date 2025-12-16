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

local curfew = engage("seeds.curfew", {
    triggerHour = 21,
    triggerMinute = 0,
    snoozeInterval = 1,  -- 1 minute between escalations
    resetHour = 4,
    holdDurations = {5, 10, 20, 40, 60}
})

local superwhisper = engage("seeds.superwhisper", {})

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
if curfew then seeds.curfew = curfew end
if superwhisper then seeds.superwhisper = superwhisper end

local hs_global_modifier = {"cmd", "ctrl"}

-- Global window filter for CLI window-switcher (kept active for instant queries)
_G.windowFilter = hs.window.filter.new(true):setCurrentSpace(nil):keepActive()

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

-- Pymodoro notification with countdown and must-click canvas overlay
local pomodoroSound = nil
local pomodoroSoundTimer = nil
local pomodoroCountdownTimers = {}
local pomodoroCanvas = nil
local pomodoroNotification = nil

-- Helper: Cleanup state without triggering dismiss actions
local function pomodoroCleanup()
    -- Cancel countdown timers
    for _, timer in ipairs(pomodoroCountdownTimers) do
        if timer then timer:stop() end
    end
    pomodoroCountdownTimers = {}

    -- Stop sound
    if pomodoroSoundTimer then
        pomodoroSoundTimer:stop()
        pomodoroSoundTimer = nil
    end
    if pomodoroSound then
        pomodoroSound:stop()
        pomodoroSound = nil
    end

    -- Delete canvas
    if pomodoroCanvas then
        pomodoroCanvas:delete()
        pomodoroCanvas = nil
    end

    -- Withdraw notification silently (set nil first to prevent callback loop)
    local notif = pomodoroNotification
    pomodoroNotification = nil
    if notif then
        notif:withdraw()
    end
end

-- Helper: Dismiss action (when user clicks notification or canvas)
local function pomodoroOnDismiss()
    pomodoroCleanup()

    -- Signal pymodoro to continue to next session
    local pidFile = os.getenv("HOME") .. "/.local/state/pymodoro/pymodoro.pid"
    local f = io.open(pidFile, "r")
    if f then
        local pid = f:read("*l")
        f:close()
        if pid then
            hs.execute("/bin/kill -SIGUSR1 " .. pid)
        end
    end

    -- Activate Kitty
    hs.application.launchOrFocus("kitty")
end

-- Helper: Show the must-click canvas overlay
local function showPomodoroCanvas(title, message)
    local screen = hs.screen.mainScreen()
    local frame = screen:frame()

    local boxWidth = 500
    local boxHeight = 200
    local x = frame.x + (frame.w - boxWidth) / 2
    local y = frame.y + (frame.h - boxHeight) / 2

    pomodoroCanvas = hs.canvas.new({x = x, y = y, w = boxWidth, h = boxHeight})
    pomodoroCanvas:level(hs.canvas.windowLevels.screenSaver)
    pomodoroCanvas:behavior(hs.canvas.windowBehaviors.canJoinAllSpaces + hs.canvas.windowBehaviors.stationary)

    -- Background
    pomodoroCanvas[1] = {
        type = "rectangle",
        action = "fill",
        fillColor = {red = 0.1, green = 0.1, blue = 0.1, alpha = 0.95},
        roundedRectRadii = {xRadius = 12, yRadius = 12}
    }

    -- Border
    pomodoroCanvas[2] = {
        type = "rectangle",
        action = "stroke",
        strokeColor = {red = 1, green = 0.4, blue = 0.4, alpha = 1},
        strokeWidth = 3,
        roundedRectRadii = {xRadius = 12, yRadius = 12}
    }

    -- Title text
    pomodoroCanvas[3] = {
        type = "text",
        text = title or "Pymodoro",
        textColor = {red = 1, green = 1, blue = 1, alpha = 1},
        textSize = 28,
        textAlignment = "center",
        frame = {x = 20, y = 40, w = boxWidth - 40, h = 40}
    }

    -- Message text
    pomodoroCanvas[4] = {
        type = "text",
        text = message or "",
        textColor = {red = 0.8, green = 0.8, blue = 0.8, alpha = 1},
        textSize = 18,
        textAlignment = "center",
        frame = {x = 20, y = 90, w = boxWidth - 40, h = 30}
    }

    -- Click to dismiss instruction
    pomodoroCanvas[5] = {
        type = "text",
        text = "Click anywhere to dismiss",
        textColor = {red = 0.5, green = 0.5, blue = 0.5, alpha = 1},
        textSize = 14,
        textAlignment = "center",
        frame = {x = 20, y = 150, w = boxWidth - 40, h = 25}
    }

    pomodoroCanvas:clickActivating(false)
    pomodoroCanvas:mouseCallback(function(canvas, event, id, x, y)
        if event == "mouseUp" then
            pomodoroOnDismiss()
        end
    end)

    pomodoroCanvas:show()
end

-- Alert style for countdown (top edge)
local pomodoroAlertStyle = {
    atScreenEdge = 1,
    textSize = 36,
    strokeColor = {red = 1, green = 0.3, blue = 0.3, alpha = 1},
    fillColor = {red = 0.15, green = 0.1, blue = 0.1, alpha = 0.95},
    textColor = {red = 1, green = 1, blue = 1, alpha = 1},
    strokeWidth = 3,
    radius = 12,
    padding = 20
}

function pomodoroNotify(title, message, soundPath)
    -- Clean up any existing state (without sending signal)
    pomodoroCleanup()

    -- Default sound if not specified
    soundPath = soundPath or "/System/Library/Sounds/Glass.aiff"

    -- 1. Show silent notification (can be clicked to dismiss early)
    pomodoroNotification = hs.notify.new(function(notification)
        pomodoroOnDismiss()
    end, {
        title = title or "Pymodoro",
        informativeText = message or "",
        withdrawAfter = 0,
        hasActionButton = true,
        actionButtonTitle = "Go to Kitty",
        soundName = ""  -- Empty string = silent
    })
    pomodoroNotification:send()

    -- 2. Start sound loop
    pomodoroSound = hs.sound.getByFile(soundPath)
    if pomodoroSound then
        pomodoroSound:play()
        pomodoroSoundTimer = hs.timer.doEvery(pomodoroSound:duration() + 0.5, function()
            if pomodoroSound then
                pomodoroSound:play()
            end
        end)
    end

    -- 3. Schedule countdown alerts (2m, 1m30s, 1m, 30s, 10s, 5s, 3s, 2s, 1s)
    local countdownSeconds = 120 -- 2 minutes
    local alertTimes = {
        {delay = 0, text = "2:00"},
        {delay = 30, text = "1:30"},
        {delay = 60, text = "1:00"},
        {delay = 90, text = "0:30"},
        {delay = 110, text = "0:10"},
        {delay = 115, text = "0:05"},
        {delay = 117, text = "0:03"},
        {delay = 118, text = "0:02"},
        {delay = 119, text = "0:01"}
    }

    for _, alert in ipairs(alertTimes) do
        local timer = hs.timer.doAfter(alert.delay, function()
            hs.alert.show(alert.text, pomodoroAlertStyle, 3)
        end)
        table.insert(pomodoroCountdownTimers, timer)
    end

    -- 4. Schedule canvas overlay after countdown
    local canvasTimer = hs.timer.doAfter(countdownSeconds, function()
        showPomodoroCanvas(title, message)
    end)
    table.insert(pomodoroCountdownTimers, canvasTimer)
end
