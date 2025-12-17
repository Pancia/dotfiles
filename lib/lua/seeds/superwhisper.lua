local obj = {}

-- Configuration
obj.state_file = os.getenv("HOME") .. "/.local/state/superwhisper_seconds"

-- Internal state
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

-- Check if SuperWhisper has recording window open (non-standard floating panel)
function obj:hasRecordingWindow()
  local app = hs.application.get("superwhisper")
  if app then
    for _, w in ipairs(app:allWindows()) do
      if not w:isStandard() then
        return true
      end
    end
  end
  return false
end

-- Sync state: called from Karabiner, checks actual SuperWhisper state
-- Starts tracking if recording window is open, stops if closed
function obj:sync()
  local recording = self:hasRecordingWindow()

  if recording and not self._start_time then
    -- Recording started - begin tracking
    self._start_time = hs.timer.secondsSinceEpoch()
    return true
  elseif not recording and self._start_time then
    -- Recording stopped - save duration
    local duration = hs.timer.secondsSinceEpoch() - self._start_time
    self:addSeconds(duration)
    self._start_time = nil
    return false
  end

  -- No state change
  return recording
end

-- Check if currently tracking
function obj:isTracking()
  return self._start_time ~= nil
end

function obj:start(config)
  config = config or {}
  if config.state_file then
    self.state_file = config.state_file
  end
  return self
end

function obj:stop()
  -- Save any in-progress recording before stopping
  if self._start_time then
    local duration = hs.timer.secondsSinceEpoch() - self._start_time
    self:addSeconds(duration)
    self._start_time = nil
  end
end

-- Export global function for hs -c access
_G.superwhisperSync = function() return obj:sync() end

return obj
