local obj = {}
local log = hs.logger.new("superwhisper", "debug")

-- Configuration
obj.state_file = os.getenv("HOME") .. "/.local/state/my-superwhisper/active"
obj.mic_active_bin = os.getenv("HOME") .. "/.local/bin/mic-active"
obj.poll_interval = 3 -- seconds
obj.startup_grace = 3 -- how many missed polls before giving up

-- Internal state
obj._poll_timer = nil
obj._initial_timer = nil
obj._escape_tap = nil
obj._last_tick = nil
obj._mic_was_on = false
obj._missed_count = 0
obj._session_added = 0 -- track how much we've added this session (for cancel/undo)

-- Read current total
function obj:getTotal()
  local file = io.open(self.state_file, "r")
  if not file then return 0 end
  local content = file:read("*a")
  local total = tonumber(content) or 0
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
  self._session_added = self._session_added + duration
  return total
end

-- Check if mic is currently active (exit 0 = active, exit 1 = inactive)
function obj:_checkMic()
  local ok = os.execute(self.mic_active_bin)
  return ok == true
end

-- Poll callback: check mic state, accumulate or stop
function obj:_poll()
  local now = hs.timer.secondsSinceEpoch()
  local micOn = self:_checkMic()

  if micOn then
    if self._last_tick then
      local elapsed = now - self._last_tick
      self:addSeconds(elapsed)
      local total = self:getTotal()
      hs.alert.show("🎙 +" .. math.floor(elapsed) .. "s (total: " .. total .. "s)", 1)
      log.d("poll: mic active, added", math.floor(elapsed), "s")
    else
      hs.alert.show("🎙 Mic active, tracking started", 1.5)
      log.i("poll: mic activated, starting accumulation")
    end
    self._last_tick = now
    self._mic_was_on = true
    self._missed_count = 0
  else
    if self._mic_was_on then
      -- Was on, now off — recording ended
      if self._last_tick then
        local elapsed = now - self._last_tick
        self:addSeconds(elapsed)
        log.i("poll: mic off, added final", math.floor(elapsed), "s")
      end
      local total = self:getTotal()
      hs.alert.show("🎙 Recording done (total: " .. total .. "s)", 2)
      log.i("poll: recording complete")
      self:_stopPolling()
    else
      -- Mic never came on yet — grace period
      self._missed_count = self._missed_count + 1
      log.d("poll: waiting for mic, attempt", self._missed_count)
      if self._missed_count >= self.startup_grace then
        hs.alert.show("🎙 Mic never activated, giving up", 2)
        log.i("poll: mic never activated, giving up")
        self:_stopPolling()
      end
    end
  end
end

function obj:_stopPolling()
  if self._poll_timer then
    self._poll_timer:stop()
    self._poll_timer = nil
  end
  if self._initial_timer then
    self._initial_timer:stop()
    self._initial_timer = nil
  end
  if self._escape_tap then
    self._escape_tap:stop()
    self._escape_tap = nil
  end
  self._last_tick = nil
  self._mic_was_on = false
  self._missed_count = 0
  self._session_added = 0
end

-- Check if currently polling
function obj:isTracking()
  return self._poll_timer ~= nil or self._initial_timer ~= nil
end

-- Called from Karabiner after voicetotext activates SuperWhisper
function obj:sync()
  if self:isTracking() then
    log.d("sync: already polling, ignoring")
    return true
  end

  hs.alert.show("🎙 Listening for mic...", 1.5)
  log.i("sync: starting mic-active polling")
  self._mic_was_on = false
  self._missed_count = 0
  self._last_tick = nil
  self._session_added = 0

  -- Listen for escape to cancel
  self._escape_tap = hs.eventtap.new({hs.eventtap.event.types.keyDown}, function(event)
    if event:getKeyCode() == hs.keycodes.map["escape"] then
      log.i("escape pressed while tracking, cancelling")
      _G.superwhisperCancel()
    end
    return false -- pass escape through to apps
  end)
  self._escape_tap:start()

  -- First check after 1s (give mic time to activate), then every poll_interval
  self._initial_timer = hs.timer.doAfter(1, function()
    self._initial_timer = nil
    self:_poll()
  end)
  self._poll_timer = hs.timer.doEvery(self.poll_interval, function()
    self:_poll()
  end)

  return true
end

function obj:start(config)
  config = config or {}
  if config.state_file then
    self.state_file = config.state_file
  end
  if config.mic_active_bin then
    self.mic_active_bin = config.mic_active_bin
  end
  log.i("start: ready, state_file:", self.state_file)
  return self
end

function obj:stop()
  -- Save any in-progress tracking before stopping
  if self._last_tick then
    local duration = hs.timer.secondsSinceEpoch() - self._last_tick
    log.i("stop: saving in-progress recording,", math.floor(duration), "s")
    self:addSeconds(duration)
  end
  self:_stopPolling()
end

-- Export global functions for hs -c access
_G.superwhisperSync = function()
  obj:sync()
  return true
end

_G.superwhisperCancel = function()
  if obj:isTracking() and obj._session_added > 0 then
    local undone = obj._session_added
    local total = obj:getTotal() - undone
    if total < 0 then total = 0 end
    obj:saveTotal(total)
    hs.alert.show("🎙 Cancelled, undid " .. math.floor(undone) .. "s", 2)
    log.i("cancel: subtracted", math.floor(undone), "s from total")
  end
  obj:_stopPolling()
  return true
end

return obj
