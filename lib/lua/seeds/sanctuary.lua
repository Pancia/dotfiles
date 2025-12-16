local obj = {}
obj._name = "sanctuary"
obj._logger = hs.logger.new("sanctuary", "info")

local CHECK_INTERVAL = 30  -- 30-second heartbeat
local VPC_PATH = "/Users/anthony/dotfiles/vpc/sanctuary.vpc"

local kittyNotification = nil
local pomodoroNotification = nil

function obj.isKittyRunning()
  local output, status = hs.execute("pgrep -x kitty")
  return status
end

function obj.isPomodoroRunning()
  local output, status = hs.execute("pgrep -f pymodoro")
  return status
end

function obj.checkKitty()
  if not obj.isKittyRunning() then
    obj._logger.i("Kitty not running, sending notification")

    if kittyNotification then
      kittyNotification:withdraw()
      kittyNotification = nil
    end

    kittyNotification = hs.notify.new(function()
      kittyNotification = nil
      hs.task.new("/usr/bin/open", nil, {VPC_PATH}):start()
    end, {
      title = "Sanctuary",
      informativeText = "Kitty is not running. Click to open workspace.",
      withdrawAfter = 0,
      hasActionButton = true,
      actionButtonTitle = "Open VPC",
      soundName = "default"
    })
    kittyNotification:send()
    return false
  end
  return true
end

function obj.checkPomodoro()
  if not obj.isPomodoroRunning() then
    obj._logger.i("Pymodoro not running, sending reminder")

    if pomodoroNotification then
      pomodoroNotification:withdraw()
      pomodoroNotification = nil
    end

    pomodoroNotification = hs.notify.new(function()
      pomodoroNotification = nil
      hs.application.launchOrFocus("kitty")
    end, {
      title = "Start a Focus Session",
      informativeText = "Pymodoro is not running",
      withdrawAfter = 0,
      soundName = "default",
      hasActionButton = true,
      actionButtonTitle = "Open Kitty"
    })
    pomodoroNotification:send()
    return false
  end
  return true
end

function obj.heartbeat()
  obj._logger.i("Heartbeat: checking Kitty and Pymodoro")

  -- Check Kitty first; if not running, skip Pymodoro check
  -- (user needs workspace open before starting a session)
  if not obj.checkKitty() then
    return
  end

  obj.checkPomodoro()
end

function obj.start(config)
  obj._logger.i("Starting sanctuary monitor (30s heartbeat)")
  obj._timer = hs.timer.doEvery(CHECK_INTERVAL, obj.heartbeat)
  hs.timer.doAfter(10, obj.heartbeat)
  return obj
end

function obj.stop()
  if obj._timer then
    obj._timer:stop()
    obj._timer = nil
  end
  if kittyNotification then
    kittyNotification:withdraw()
    kittyNotification = nil
  end
  if pomodoroNotification then
    pomodoroNotification:withdraw()
    pomodoroNotification = nil
  end
end

return obj
