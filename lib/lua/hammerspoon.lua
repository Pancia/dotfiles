-- CONTEXT: [[~/dotfiles/wiki/HammerSpoon.wiki]]
local _coreStart = hs.timer.absoluteTime()

local HOME = os.getenv("HOME")

local _spoonStart = hs.timer.absoluteTime()
local install = hs.loadSpoon("SpoonInstall")
install.use_syncinstall = true

-- ClipboardTool replaced by seeds.clipboard (encrypted)

install:andUse("FadeLogo", {
  start = true,
  config = {default_run = 1.0}
})
table.insert(_G._profile, string.format("  spoons: %.1fms", (hs.timer.absoluteTime() - _spoonStart) / 1e6))

function engage(seed_path, config)
  local start = hs.timer.absoluteTime()
  local success, result = pcall(function()
    local seed = require(seed_path)
    seed:start(config)
    return seed
  end)
  local elapsed = (hs.timer.absoluteTime() - start) / 1e6

  if not success then
    hs.notify.new({
      title = "Hammerspoon Seed Error",
      informativeText = string.format("Failed to load '%s': %s", seed_path, result),
      withdrawAfter = 10
    }):send()
    hs.printf("\n\n=== SEED ERROR: %s ===\n%s\n\n", seed_path, result)
    return nil
  end

  table.insert(_G._profile, string.format("    %s: %.1fms", seed_path, elapsed))
  return result
end

local _engageStart = hs.timer.absoluteTime()

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

local curfew = nil
--engage("seeds.curfew", {
--    triggerTime = {hour = 22, minute = 30},
--    resetTime = {hour = 6, minute = 0},
--    holdDuration = 15
--})

local superwhisper = engage("seeds.superwhisper", {})

local clipboard = engage("seeds.clipboard", {
  hotkey = {{"cmd", "ctrl"}, "p"},
  hist_size = 50,
  storage_path = HOME .. "/ProtonDrive/hammerspoon/clipboard_history.enc"
})

local hermes = engage("seeds.hermes.init", {
  hotkey = {{"cmd"}, "space"},
})

local cursor = engage("seeds.cursor", {
  hotkey = {{"cmd", "ctrl"}, "m"},
  style = "circle",  -- "circle", "crosshair", or "ring"
  size = 32,
  strokeWidth = 3,
  strokeColor = {red = 0.7, green = 0.3, blue = 1, alpha = 0.95},
})

local _engageElapsed = (hs.timer.absoluteTime() - _engageStart) / 1e6
table.insert(_G._profile, string.format("  seeds: %.1fms", _engageElapsed))

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
if clipboard then seeds.clipboard = clipboard end
if cmus then seeds.cmus = cmus end
if hermes then seeds.hermes = hermes end
if cursor then seeds.cursor = cursor end

local hs_global_modifier = {"cmd", "ctrl"}

hs.hotkey.bindSpec({hs_global_modifier, "c"}, hs.toggleConsole)

-- Soft reload: reloads code without destroying menubars
-- Menubars persist via lib/menubarRegistry, preserving Hidden Bar visibility
local function softReload()
    hs.alert.show("⟳ Soft reloading...", 1)

    local softReloadProfile = {}
    local totalStart = hs.timer.absoluteTime()

    -- Phase 1: Stop seeds (softStop if available, else regular stop)
    for name, seed in pairs(seeds) do
        local start = hs.timer.absoluteTime()
        local ok, err

        if seed.softStop then
            ok, err = pcall(function() seed:softStop() end)
        elseif seed.stop then
            ok, err = pcall(function() seed:stop() end)
        else
            ok = true
        end

        local elapsed = (hs.timer.absoluteTime() - start) / 1e6
        if not ok then
            table.insert(softReloadProfile, string.format("  ERROR %s: %s", name, err))
        else
            local method = seed.softStop and "softStop" or "stop"
            table.insert(softReloadProfile, string.format("  %s %s: %.1fms", method, name, elapsed))
        end
    end

    -- Phase 2: Clear module cache for seeds (NOT menubarRegistry)
    local seedModules = {
        "seeds.monitor",
        "seeds.cmus",
        "seeds.snippets",
        "seeds.calendar.init",
        "seeds.lotus.init",
        "seeds.watch.init",
        "seeds.sanctuary",
        "seeds.curfew",
        "seeds.superwhisper",
        "seeds.clipboard",
        "seeds.hermes.init",
        "seeds.hermes.commands",
        "seeds.cursor",
    }

    for _, modulePath in ipairs(seedModules) do
        package.loaded[modulePath] = nil
    end

    -- Phase 3: Clear hammerspoon.lua itself and re-require
    package.loaded["hammerspoon"] = nil

    local totalElapsed = (hs.timer.absoluteTime() - totalStart) / 1e6
    table.insert(softReloadProfile, string.format("soft reload cleanup: %.1fms", totalElapsed))
    hs.printf("[profile:softReload]\n%s", table.concat(softReloadProfile, "\n"))

    -- Phase 4: Re-require hammerspoon (this re-engages all seeds)
    require("hammerspoon")

    hs.alert.show("✓ Soft reload complete", 1.5)
end

-- Soft reload (default) - preserves menubars for Hidden Bar
hs.hotkey.bindSpec({hs_global_modifier, "r"}, softReload)

-- Hard reload (fallback) - full restart, destroys all state
hs.hotkey.bindSpec({{"cmd", "ctrl", "shift"}, "r"}, function()
  local reload_flag = "/tmp/hs_reloading"
  local file = io.open(reload_flag, "w")
  if file then
    file:write("true")
    file:close()
  end

  hs.alert.show("⟳ Hard reloading...", 1)

  local stopProfile = {}
  local totalStart = hs.timer.absoluteTime()
  for name, seed in pairs(seeds) do
    if seed.stop then
      local start = hs.timer.absoluteTime()
      local ok, err = pcall(function() seed:stop() end)
      local elapsed = (hs.timer.absoluteTime() - start) / 1e6 -- convert to ms
      if not ok then
        table.insert(stopProfile, string.format("  ERROR %s: %s", name, err))
      else
        table.insert(stopProfile, string.format("  %s: %.1fms", name, elapsed))
      end
    end
  end
  local totalElapsed = (hs.timer.absoluteTime() - totalStart) / 1e6
  table.insert(stopProfile, string.format("stop total: %.1fms", totalElapsed))
  hs.printf("[profile:stop]\n%s", table.concat(stopProfile, "\n"))

  hs.timer.doAfter(0.3, function()
    hs.reload()
  end)
end)

-- Show reload complete notification
if is_reloading() then
  hs.alert.show("✓ Hammerspoon reloaded", 1.5)
end

table.insert(_G._profile, string.format("  core: %.1fms", (hs.timer.absoluteTime() - _coreStart) / 1e6))

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
    -- Withdraw all existing Sanctuary notifications
    for _, notif in ipairs(hs.notify.deliveredNotifications()) do
        if notif:title() == "Sanctuary" then
            notif:withdraw()
        end
    end
    sanctuaryNotification = nil

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
local pomodoroOverlays = {}  -- one overlay per screen
local pomodoroNotification = nil
local pomodoroMouseDownTap = nil
local pomodoroMouseUpTap = nil
local pomodoroIsShowingOverlay = false

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

    -- Clean up eventtaps
    if pomodoroMouseDownTap then
        pomodoroMouseDownTap:stop()
        pomodoroMouseDownTap = nil
    end
    if pomodoroMouseUpTap then
        pomodoroMouseUpTap:stop()
        pomodoroMouseUpTap = nil
    end

    -- Delete all overlays
    pomodoroIsShowingOverlay = false
    for _, overlay in ipairs(pomodoroOverlays) do
        overlay:delete()
    end
    pomodoroOverlays = {}

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

    -- Activate Kitty (user interacts with pymodoro directly to continue)
    hs.application.launchOrFocus("kitty")
end

-- Helper: Create full-screen overlay for a single screen
local function createPomodoroOverlayForScreen(screen, title, message)
    local frame = screen:frame()
    local fullFrame = screen:fullFrame()

    local boxWidth = 500
    local boxHeight = 250
    local centerX = frame.w / 2
    local centerY = frame.h / 2
    local boxX = centerX - boxWidth / 2
    local boxY = centerY - boxHeight / 2

    local overlay = hs.canvas.new(fullFrame)
    overlay:level(hs.canvas.windowLevels.screenSaver)
    overlay:behavior(hs.canvas.windowBehaviors.canJoinAllSpaces + hs.canvas.windowBehaviors.stationary)

    -- Full screen dim background
    overlay[1] = {
        type = "rectangle",
        action = "fill",
        fillColor = {red = 0.05, green = 0.08, blue = 0.05, alpha = 0.9}
    }

    -- Central dialog box
    overlay[2] = {
        type = "rectangle",
        action = "fill",
        frame = {x = boxX, y = boxY, w = boxWidth, h = boxHeight},
        fillColor = {red = 0.1, green = 0.12, blue = 0.1, alpha = 1},
        roundedRectRadii = {xRadius = 16, yRadius = 16}
    }

    -- Dialog border
    overlay[3] = {
        type = "rectangle",
        action = "stroke",
        frame = {x = boxX, y = boxY, w = boxWidth, h = boxHeight},
        strokeColor = {red = 0.4, green = 0.7, blue = 0.4, alpha = 1},
        strokeWidth = 2,
        roundedRectRadii = {xRadius = 16, yRadius = 16}
    }

    -- Break icon (green circle)
    overlay[4] = {
        type = "circle",
        action = "fill",
        center = {x = centerX, y = boxY + 45},
        radius = 20,
        fillColor = {red = 0.4, green = 0.8, blue = 0.4, alpha = 1}
    }

    -- Title
    overlay[5] = {
        type = "text",
        text = title or "Break Time",
        textColor = {red = 1, green = 1, blue = 1, alpha = 1},
        textSize = 28,
        textAlignment = "center",
        frame = {x = boxX + 20, y = boxY + 80, w = boxWidth - 40, h = 40}
    }

    -- Message
    overlay[6] = {
        type = "text",
        text = message or "",
        textColor = {red = 0.7, green = 0.7, blue = 0.7, alpha = 1},
        textSize = 18,
        textAlignment = "center",
        frame = {x = boxX + 20, y = boxY + 125, w = boxWidth - 40, h = 30}
    }

    -- Instructions
    overlay[7] = {
        type = "text",
        text = "Click anywhere to dismiss and continue",
        textColor = {red = 0.5, green = 0.5, blue = 0.5, alpha = 1},
        textSize = 14,
        textAlignment = "center",
        frame = {x = boxX + 20, y = boxY + boxHeight - 50, w = boxWidth - 40, h = 25}
    }

    overlay:clickActivating(false)
    overlay:show()

    return overlay
end

-- Helper: Show the must-click full-screen overlay on all screens
function showPomodoroCanvas(title, message)
    pomodoroIsShowingOverlay = true

    -- Create overlay on all screens
    for _, screen in ipairs(hs.screen.allScreens()) do
        local overlay = createPomodoroOverlayForScreen(screen, title, message)
        table.insert(pomodoroOverlays, overlay)
    end

    -- Set up eventtaps to capture mouse input
    pomodoroMouseDownTap = hs.eventtap.new({hs.eventtap.event.types.leftMouseDown}, function(event)
        if pomodoroIsShowingOverlay then
            return true  -- consume the event
        end
        return false
    end)

    pomodoroMouseUpTap = hs.eventtap.new({hs.eventtap.event.types.leftMouseUp}, function(event)
        if pomodoroIsShowingOverlay then
            pomodoroOnDismiss()
            return true  -- consume the event
        end
        return false
    end)

    pomodoroMouseDownTap:start()
    pomodoroMouseUpTap:start()
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
    pomodoroSound = nil --hs.sound.getByFile(soundPath)
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

-- ============================================================================
-- Break Overlay: Fullscreen overlay during breaks
-- ============================================================================

-- Break overlay state
local breakOverlays = {}
local breakOverlayTimer = nil
local breakOverlayDismissable = false
local breakMouseDownTap = nil
local breakMouseUpTap = nil
local breakKeyboardTap = nil
local breakIsShowingOverlay = false
local breakHoldStartTime = nil
local breakProgressTimer = nil
local BREAK_PANIC_HOLD_DURATION = 10  -- seconds to hold for early dismiss

-- Helper: Create break overlay for a single screen
local function createBreakOverlayForScreen(screen, label, durationMinutes)
    local frame = screen:frame()
    local fullFrame = screen:fullFrame()

    local boxWidth = 500
    local boxHeight = 350
    local centerX = frame.w / 2
    local centerY = frame.h / 2
    local boxX = centerX - boxWidth / 2
    local boxY = centerY - boxHeight / 2

    -- Progress ring position
    local ringCenterY = boxY + 220
    local ringRadius = 40

    local overlay = hs.canvas.new(fullFrame)
    overlay:level(hs.canvas.windowLevels.screenSaver)
    overlay:behavior(hs.canvas.windowBehaviors.canJoinAllSpaces + hs.canvas.windowBehaviors.stationary)

    -- Full screen dim background (calming blue tint)
    overlay[1] = {
        type = "rectangle",
        action = "fill",
        fillColor = {red = 0.03, green = 0.05, blue = 0.1, alpha = 0.92}
    }

    -- Central dialog box
    overlay[2] = {
        type = "rectangle",
        action = "fill",
        frame = {x = boxX, y = boxY, w = boxWidth, h = boxHeight},
        fillColor = {red = 0.08, green = 0.1, blue = 0.15, alpha = 1},
        roundedRectRadii = {xRadius = 16, yRadius = 16}
    }

    -- Dialog border (soft blue)
    overlay[3] = {
        type = "rectangle",
        action = "stroke",
        frame = {x = boxX, y = boxY, w = boxWidth, h = boxHeight},
        strokeColor = {red = 0.3, green = 0.5, blue = 0.7, alpha = 1},
        strokeWidth = 2,
        roundedRectRadii = {xRadius = 16, yRadius = 16}
    }

    -- Coffee icon (text-based)
    overlay[4] = {
        type = "text",
        text = "☕",
        textColor = {red = 0.9, green = 0.85, blue = 0.7, alpha = 1},
        textSize = 48,
        textAlignment = "center",
        frame = {x = boxX, y = boxY + 30, w = boxWidth, h = 60}
    }

    -- Title
    overlay[5] = {
        id = "title",
        type = "text",
        text = "Take a break",
        textColor = {red = 1, green = 1, blue = 1, alpha = 1},
        textSize = 28,
        textAlignment = "center",
        frame = {x = boxX + 20, y = boxY + 90, w = boxWidth - 40, h = 40}
    }

    -- Label (if provided)
    local labelText = label and label ~= "" and label or ""
    overlay[6] = {
        type = "text",
        text = labelText,
        textColor = {red = 0.6, green = 0.6, blue = 0.7, alpha = 1},
        textSize = 16,
        textAlignment = "center",
        frame = {x = boxX + 20, y = boxY + 130, w = boxWidth - 40, h = 25}
    }

    -- Duration display
    local durationText = string.format("%d minute%s", durationMinutes, durationMinutes == 1 and "" or "s")
    overlay[11] = {
        type = "text",
        text = durationText,
        textColor = {red = 0.5, green = 0.6, blue = 0.7, alpha = 1},
        textSize = 18,
        textAlignment = "center",
        frame = {x = boxX + 20, y = boxY + 160, w = boxWidth - 40, h = 25}
    }

    -- Progress ring background (for panic button)
    overlay[7] = {
        type = "circle",
        action = "stroke",
        center = {x = centerX, y = ringCenterY},
        radius = ringRadius,
        strokeColor = {red = 0.2, green = 0.2, blue = 0.25, alpha = 1},
        strokeWidth = 6
    }

    -- Progress ring (fills as you hold - for panic exit)
    overlay[8] = {
        id = "ringProgress",
        type = "arc",
        center = {x = centerX, y = ringCenterY},
        radius = ringRadius,
        startAngle = -90,
        endAngle = -90,
        strokeColor = {red = 0.7, green = 0.4, blue = 0.4, alpha = 1},
        strokeWidth = 6,
        action = "stroke"
    }

    -- Hold duration text inside ring
    overlay[9] = {
        id = "holdText",
        type = "text",
        text = "",
        textColor = {red = 0.6, green = 0.6, blue = 0.6, alpha = 1},
        textSize = 14,
        textAlignment = "center",
        frame = {x = centerX - 30, y = ringCenterY - 10, w = 60, h = 20}
    }

    -- Instructions
    overlay[10] = {
        id = "instructions",
        type = "text",
        text = "Hold mouse button 10s for emergency exit",
        textColor = {red = 0.35, green = 0.35, blue = 0.4, alpha = 1},
        textSize = 12,
        textAlignment = "center",
        frame = {x = boxX + 20, y = boxY + boxHeight - 40, w = boxWidth - 40, h = 20}
    }

    overlay:clickActivating(false)
    overlay:show()

    return overlay
end

-- Forward declarations
local breakOverlayCleanup
local breakOverlayDismiss
local breakStartHold
local breakEndHold
local breakUpdateProgress
local breakResetProgress

-- Helper: Update progress ring during hold
breakUpdateProgress = function(elapsed)
    if #breakOverlays == 0 then return end

    local progress = math.min(elapsed / BREAK_PANIC_HOLD_DURATION, 1)
    local endAngle = -90 + (360 * progress)

    for _, overlay in ipairs(breakOverlays) do
        overlay[8].endAngle = endAngle
        overlay[9].text = string.format("%.0fs", math.ceil(BREAK_PANIC_HOLD_DURATION - elapsed))
    end
end

-- Helper: Reset progress ring
breakResetProgress = function()
    if #breakOverlays == 0 then return end
    for _, overlay in ipairs(breakOverlays) do
        overlay[8].endAngle = -90
        overlay[9].text = ""
    end
end

-- Helper: Start hold for panic exit
breakStartHold = function()
    breakHoldStartTime = hs.timer.secondsSinceEpoch()

    if breakProgressTimer then
        breakProgressTimer:stop()
    end

    breakProgressTimer = hs.timer.doEvery(0.05, function()
        if not breakHoldStartTime then return end

        local elapsed = hs.timer.secondsSinceEpoch() - breakHoldStartTime
        breakUpdateProgress(elapsed)

        if elapsed >= BREAK_PANIC_HOLD_DURATION then
            breakOverlayDismiss()
        end
    end)
end

-- Helper: End hold
breakEndHold = function()
    breakHoldStartTime = nil

    if breakProgressTimer then
        breakProgressTimer:stop()
        breakProgressTimer = nil
    end

    breakResetProgress()
end

-- Helper: Cleanup break overlay state
breakOverlayCleanup = function()
    -- Stop timers
    if breakOverlayTimer then
        breakOverlayTimer:stop()
        breakOverlayTimer = nil
    end
    if breakProgressTimer then
        breakProgressTimer:stop()
        breakProgressTimer = nil
    end

    -- Clean up eventtaps
    if breakMouseDownTap then
        breakMouseDownTap:stop()
        breakMouseDownTap = nil
    end
    if breakMouseUpTap then
        breakMouseUpTap:stop()
        breakMouseUpTap = nil
    end
    if breakKeyboardTap then
        breakKeyboardTap:stop()
        breakKeyboardTap = nil
    end

    -- Reset state
    breakHoldStartTime = nil
    breakIsShowingOverlay = false
    breakOverlayDismissable = false

    -- Delete all overlays
    for _, overlay in ipairs(breakOverlays) do
        overlay:delete()
    end
    breakOverlays = {}
end

-- Helper: Dismiss break overlay
breakOverlayDismiss = function()
    breakOverlayCleanup()

    -- Activate Kitty (user interacts with pymodoro directly to continue)
    hs.application.launchOrFocus("kitty")
end

-- Helper: Setup event taps to block input
local function breakSetupEventTaps()
    -- Block keyboard (but allow Cmd+Ctrl+R to reload Hammerspoon as safety escape)
    breakKeyboardTap = hs.eventtap.new({hs.eventtap.event.types.keyDown, hs.eventtap.event.types.keyUp}, function(event)
        if breakIsShowingOverlay then
            local flags = event:getFlags()
            local keyCode = event:getKeyCode()
            -- Allow Cmd+Ctrl+R (keyCode 15 = 'r') to reload Hammerspoon
            if flags.cmd and flags.ctrl and keyCode == 15 then
                return false  -- let it through
            end
            return true  -- consume all other keyboard events
        end
        return false
    end)

    -- Mouse down - start hold timer
    breakMouseDownTap = hs.eventtap.new({hs.eventtap.event.types.leftMouseDown}, function(event)
        if breakIsShowingOverlay then
            if breakOverlayDismissable then
                -- Normal dismiss when break is over
                breakOverlayDismiss()
            else
                -- Start panic hold
                breakStartHold()
            end
            return true
        end
        return false
    end)

    -- Mouse up - cancel hold if not complete
    breakMouseUpTap = hs.eventtap.new({hs.eventtap.event.types.leftMouseUp}, function(event)
        if breakIsShowingOverlay then
            if breakHoldStartTime then
                breakEndHold()
            end
            return true
        end
        return false
    end)

    breakKeyboardTap:start()
    breakMouseDownTap:start()
    breakMouseUpTap:start()
end

-- Helper: Enable dismissal (called when break timer expires)
local function breakOverlayEnableDismiss()
    breakOverlayDismissable = true

    -- Update overlay text
    for _, overlay in ipairs(breakOverlays) do
        overlay[5].text = "Break complete"
        overlay[5].textColor = {red = 0.5, green = 0.8, blue = 0.5, alpha = 1}
        overlay[10].text = "Click anywhere to continue"
        overlay[10].textColor = {red = 0.5, green = 0.7, blue = 0.5, alpha = 1}
        -- Hide the progress ring when dismissable
        overlay[7].strokeColor = {red = 0, green = 0, blue = 0, alpha = 0}
        overlay[8].strokeColor = {red = 0, green = 0, blue = 0, alpha = 0}
    end

    -- Play a subtle sound to indicate break is over
    hs.sound.getByName("Glass"):play()
end

-- Main function: Show break overlay for specified duration
function breakOverlayShow(label, durationMinutes)
    -- Clean up any existing break overlay
    breakOverlayCleanup()

    -- Default to 5 minutes if not specified
    durationMinutes = durationMinutes or 5

    breakIsShowingOverlay = true
    breakOverlayDismissable = false

    -- Create overlay on all screens
    for _, screen in ipairs(hs.screen.allScreens()) do
        local overlay = createBreakOverlayForScreen(screen, label, durationMinutes)
        table.insert(breakOverlays, overlay)
    end

    -- Setup event taps to block input immediately
    breakSetupEventTaps()

    -- Schedule enable dismiss after break duration
    breakOverlayTimer = hs.timer.doAfter(durationMinutes * 60, function()
        breakOverlayEnableDismiss()
    end)
end

-- Export for hs -c access
_G.breakOverlayShow = breakOverlayShow
