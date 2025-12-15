local obj = {}
obj._name = "sanctuary"
obj._logger = hs.logger.new("sanctuary", "info")

local CHECK_INTERVAL = 300  -- 5 minutes in seconds
local activeNotification = nil

function obj.isPomodoroRunning()
  local output, status = hs.execute("pgrep -f pymodoro")
  return status
end

function obj.checkAndNotify()
  if not obj.isPomodoroRunning() then
    obj._logger.i("Pymodoro not running, sending reminder")

    -- Withdraw previous notification
    if activeNotification then
      activeNotification:withdraw()
      activeNotification = nil
    end

    activeNotification = hs.notify.new(function()
      obj._logger.i("Notification clicked, focusing kitty")
      activeNotification = nil
      hs.application.launchOrFocus("kitty")
    end, {
      title = "Start a Focus Session",
      informativeText = "Pymodoro is not running",
      withdrawAfter = 0,
      soundName = "default",
      hasActionButton = true,
      actionButtonTitle = "Open Kitty"
    })
    activeNotification:send()
  end
end

function obj.start(config)
  obj._logger.i("Starting sanctuary monitor")
  obj._timer = hs.timer.doEvery(CHECK_INTERVAL, obj.checkAndNotify)
  hs.timer.doAfter(10, obj.checkAndNotify)
  return obj
end

function obj.stop()
  if obj._timer then
    obj._timer:stop()
    obj._timer = nil
  end
end

return obj
