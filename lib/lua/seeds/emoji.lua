local obj = {}

-- Configuration
obj.hotkey = {{"cmd", "ctrl"}, "e"}

function obj:toggle()
  hs.task.new("/usr/bin/open", function() end, {
    "-na", "ghostty",
    "--args", "-e", "/opt/homebrew/bin/fish", "-c", "emoji-pick"
  }):start()
end

function obj:start(config)
  config = config or {}
  if config.hotkey then self.hotkey = config.hotkey end
  self._hotkey = hs.hotkey.bindSpec(self.hotkey, function() self:toggle() end)
  return self
end

function obj:stop()
  if self._hotkey then
    self._hotkey:delete()
    self._hotkey = nil
  end
end

return obj
