local obj = {}
local log = hs.logger.new("superwhisper", "debug")

-- Configuration
obj.state_file = os.getenv("HOME") .. "/.local/state/my-superwhisper/active"

-- Internal state
obj._start_time = nil

-- Read current total
function obj:getTotal()
  log.d("getTotal: reading from", self.state_file)
  local file = io.open(self.state_file, "r")
  if not file then
    log.d("getTotal: file not found, returning 0")
    return 0
  end
  local content = file:read("*a")
  local total = tonumber(content) or 0
  file:close()
  log.d("getTotal: read content =", content, ", total =", total)
  return total
end

-- Save total
function obj:saveTotal(seconds)
  log.d("saveTotal: saving", seconds, "seconds")
  local dir = self.state_file:match("(.*/)")
  log.d("saveTotal: ensuring dir exists:", dir)
  if dir then os.execute("mkdir -p " .. dir) end
  local file = io.open(self.state_file, "w")
  if file then
    file:write(tostring(math.floor(seconds)))
    file:close()
    log.i("saveTotal: saved", math.floor(seconds), "to", self.state_file)
  else
    log.e("saveTotal: FAILED to open state file for writing:", self.state_file)
  end
end

-- Add seconds to total
function obj:addSeconds(duration)
  log.d("addSeconds: adding", duration, "seconds")
  local total = self:getTotal() + duration
  log.d("addSeconds: new total =", total)
  self:saveTotal(total)
  return total
end

-- Check if SuperWhisper has recording window open (non-standard floating panel)
function obj:hasRecordingWindow()
  local app = hs.application.get("superwhisper")
  log.d("hasRecordingWindow: app =", app and app:name() or "nil")
  if app then
    local windows = app:allWindows()
    log.d("hasRecordingWindow: found", #windows, "windows")
    for i, w in ipairs(windows) do
      local isStd = w:isStandard()
      local title = w:title() or "(no title)"
      local role = w:role() or "(no role)"
      local subrole = w:subrole() or "(no subrole)"
      log.d("  window", i, "- standard:", isStd, "title:", title, "role:", role, "subrole:", subrole)
      if not isStd then
        log.d("hasRecordingWindow: found non-standard window, returning true")
        return true
      end
    end
  end
  log.d("hasRecordingWindow: no recording window found, returning false")
  return false
end

-- Sync state: called from Karabiner on hotkey press
-- Window OPEN = we're ENDING (stop pressed, window still open)
-- Window CLOSED = we're STARTING (start pressed, window not open yet)
function obj:sync()
  log.d("sync: called, _start_time =", self._start_time)
  local windowOpen = self:hasRecordingWindow()
  log.d("sync: windowOpen =", windowOpen, ", _start_time =", self._start_time)

  if windowOpen then
    -- Window open = we're ENDING a recording
    if self._start_time then
      local duration = hs.timer.secondsSinceEpoch() - self._start_time
      log.i("sync: recording ENDED, duration:", math.floor(duration), "seconds")
      self:addSeconds(duration)
      self._start_time = nil
    else
      log.d("sync: window open but not tracking - ignoring")
    end
    return false
  else
    -- Window closed = we're STARTING a recording
    if self._start_time then
      log.i("sync: discarding previous tracking (cancelled)")
    end
    self._start_time = hs.timer.secondsSinceEpoch()
    log.i("sync: recording STARTED at", self._start_time)
    return true
  end
end

-- Check if currently tracking
function obj:isTracking()
  return self._start_time ~= nil
end

function obj:start(config)
  log.d("start: initializing with config:", hs.inspect(config))
  config = config or {}
  if config.state_file then
    self.state_file = config.state_file
  end
  log.i("start: seed ready, state_file:", self.state_file)
  return self
end

function obj:stop()
  log.d("stop: called, _start_time =", self._start_time)
  -- Save any in-progress recording before stopping
  if self._start_time then
    local duration = hs.timer.secondsSinceEpoch() - self._start_time
    log.i("stop: saving in-progress recording, duration:", math.floor(duration), "seconds")
    self:addSeconds(duration)
    self._start_time = nil
  end
  log.d("stop: complete")
end

-- Export global function for hs -c access
_G.superwhisperSync = function()
  log.d("superwhisperSync: global function called")
  local result = obj:sync()
  log.d("superwhisperSync: returning", result)
  return result
end

return obj
