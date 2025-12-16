local obj = {}

-- Configuration
obj.state_file = os.getenv("HOME") .. "/.local/state/superwhisper_seconds"

-- Internal state
obj._filter = nil
obj._start_time = nil

-- Read current total
function obj:getTotal()
  local file = io.open(self.state_file, "r")
  if not file then return 0 end
  local total = tonumber(file:read("*a")) or 0
  file:close()
  return total
end

-- Save total
function obj:saveTotal(seconds)
  local dir = self.state_file:match("(.*/)")
  if dir then os.execute("mkdir -p " .. dir) end
  local file = io.open(self.state_file, "w")
  if file then
    file:write(tostring(math.floor(seconds)))
    file:close()
  end
end

-- Add seconds to total
function obj:addSeconds(duration)
  local total = self:getTotal() + duration
  self:saveTotal(total)
  return total
end

-- Check if SuperWhisper is currently recording
function obj:isRecording()
  local app = hs.application.get("superwhisper")
  if app then
    return #app:allWindows() > 0
  end
  return false
end

-- Handle window created
local function onWindowCreated(win)
  if not obj._start_time then
    obj._start_time = hs.timer.secondsSinceEpoch()
  end
end

-- Handle window destroyed
local function onWindowDestroyed(win)
  if obj._start_time then
    local duration = hs.timer.secondsSinceEpoch() - obj._start_time
    obj:addSeconds(duration)
    obj._start_time = nil
  end
end

function obj:start(config)
  config = config or {}
  if config.state_file then
    self.state_file = config.state_file
  end

  self._filter = hs.window.filter.new("superwhisper")
  self._filter:subscribe(hs.window.filter.windowCreated, onWindowCreated)
  self._filter:subscribe(hs.window.filter.windowDestroyed, onWindowDestroyed)

  -- Check if already recording on start
  if self:isRecording() then
    obj._start_time = hs.timer.secondsSinceEpoch()
  end

  return self
end

function obj:stop()
  if self._filter then
    self._filter:unsubscribeAll()
    self._filter = nil
  end
  self._start_time = nil
end

return obj
