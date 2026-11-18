-- Claudetheme: keep the Claude Code theme in step with the macOS appearance.
-- Runs bin/claude-theme-sync at start and whenever macOS switches between
-- light and dark. See ai/claude-themes/README.md for why.

local obj = {}
obj._name = "claudetheme"

local config = {
    script = os.getenv("HOME") .. "/dotfiles/bin/claude-theme-sync",
    delay = 1,  -- seconds: let the appearance setting settle first
}

local watcher = nil
local timer = nil

local function sync()
    hs.task.new(config.script, function(code, _, stderr)
        if code ~= 0 then
            print("claudetheme: claude-theme-sync failed: " .. (stderr or ""))
        end
    end):start()
end

function obj:start(cfg)
    for k, v in pairs(cfg or {}) do config[k] = v end
    watcher = hs.distributednotifications.new(function()
        if timer then timer:stop() end
        timer = hs.timer.doAfter(config.delay, sync)
    end, "AppleInterfaceThemeChangedNotification")
    watcher:start()
    sync()
    return self
end

function obj:stop()
    if watcher then watcher:stop(); watcher = nil end
    if timer then timer:stop(); timer = nil end
end

return obj
