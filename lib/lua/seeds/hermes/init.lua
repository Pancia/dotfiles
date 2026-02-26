-- Hermes: Fast command launcher popup
-- Uses hs.webview for instant Alfred-like experience

local obj = {}

obj.spoonPath = os.getenv("HOME") .. "/dotfiles/lib/lua/seeds/hermes/"
obj.iconCacheDir = os.getenv("HOME") .. "/.cache/app-icons"
obj.appCacheFile = os.getenv("HOME") .. "/.cache/hermes/apps.json"
obj.appDirs = {
    "/Applications",
    os.getenv("HOME") .. "/Applications",
    "/System/Applications",
    "/System/Library/CoreServices/Applications",
}

function obj:start(config)
    self.hotkey = config.hotkey or {{"cmd"}, "space"}
    self._commands = nil  -- Lazy load
    self._logger = hs.logger.new("Hermes", "info")

    self:createWebview()

    self._hotkey = hs.hotkey.bindSpec(self.hotkey, function()
        self:toggle()
    end)

    self._logger.i("Hermes started with hotkey", hs.inspect(self.hotkey))
    return self
end

function obj:loadCommands()
    -- Clear cached module to allow reloading
    package.loaded["seeds.hermes.commands"] = nil
    self._commands = require("seeds.hermes.commands")
    return self._commands
end

function obj:createWebview()
    local frame = hs.screen.primaryScreen():fullFrame()
    local width, height = 780, 480
    local rect = hs.geometry.rect(
        frame.x + (frame.w - width) / 2,
        frame.y + (frame.h - height) / 2,
        width, height
    )

    local uc = hs.webview.usercontent.new("Hermes")
    uc:setCallback(function(msg)
        self:handleMessage(msg)
    end)

    self._browser = hs.webview.newBrowser(rect, {developerExtrasEnabled = true}, uc)
    self._browser:windowStyle({"borderless"})
    self._browser:level(hs.canvas.windowLevels.floating)
    self._browser:allowTextEntry(true)
    self._browser:shadow(true)
    self._browser:closeOnEscape(false)  -- We handle escape ourselves

    -- Load HTML
    local htmlPath = self.spoonPath .. "hermes.html"
    self._browser:url("file://" .. htmlPath)

    self._logger.d("Webview created")
end

function obj:resolveDynamicTitle(title)
    -- Resolve #!fish: prefix to get dynamic title
    if type(title) == "string" and title:match("^#!fish:") then
        local cmd = title:sub(8)  -- Remove "#!fish:" prefix
        local output, status = hs.execute(cmd)
        if status then
            return output:gsub("%s+$", "")  -- Trim trailing whitespace
        else
            return "(?)"
        end
    end
    return title
end

function obj:resolveCommands(cmds)
    -- Recursively resolve commands: functions become their results, dynamic titles evaluated
    local resolved = {}
    for k, v in pairs(cmds) do
        if type(v) == "function" then
            local ok, result = pcall(v)
            if ok then
                resolved[k] = self:resolveCommands(result)  -- Recurse into result
            else
                self._logger.w("Failed to resolve generator for key", k, result)
                resolved[k] = {_desc = "Error", x = {"Error loading", "echo 'Error'"}}
            end
        elseif type(v) == "table" then
            if v._desc then
                -- Submenu - recurse
                resolved[k] = self:resolveCommands(v)
            elseif #v >= 2 then
                -- Command entry: {title, command} - resolve dynamic title
                resolved[k] = {self:resolveDynamicTitle(v[1]), v[2]}
            else
                resolved[k] = v
            end
        else
            resolved[k] = v
        end
    end
    return resolved
end

-- ============================================================================
-- APP LAUNCHER FUNCTIONS
-- ============================================================================

function obj:scanApps()
    -- Scan all application directories for .app bundles
    local apps = {}
    local seen = {}  -- Deduplicate by name (prefer user apps)

    for _, dir in ipairs(self.appDirs) do
        local iter, dirObj = hs.fs.dir(dir)
        if iter then
            for file in iter, dirObj do
                if file:match("%.app$") then
                    local name = file:gsub("%.app$", "")
                    if not seen[name] then
                        seen[name] = true
                        local path = dir .. "/" .. file
                        local iconPath = self:getAppIconPath(name)
                        table.insert(apps, {
                            name = name,
                            path = path,
                            icon = iconPath,
                            lastUsed = nil  -- Will be populated async
                        })
                    end
                end
            end
        end
    end

    -- Sort alphabetically by default
    table.sort(apps, function(a, b) return a.name:lower() < b.name:lower() end)

    return apps
end

function obj:getAppIconPath(appName)
    -- Get path to cached icon PNG
    local safeName = appName:gsub("/", "_"):gsub(" ", "_")
    return self.iconCacheDir .. "/" .. safeName .. ".png"
end

function obj:extractAppIcon(appPath, appName, callback)
    -- Extract icon from app bundle to cache (async)
    local iconPath = self:getAppIconPath(appName)

    -- Check if already cached
    if hs.fs.attributes(iconPath) then
        if callback then callback(iconPath) end
        return
    end

    -- Find .icns file in app bundle
    local resourcesDir = appPath .. "/Contents/Resources"
    local icnsPath = nil

    local iter, dirObj = hs.fs.dir(resourcesDir)
    if iter then
        for file in iter, dirObj do
            if file:match("%.icns$") then
                icnsPath = resourcesDir .. "/" .. file
                break
            end
        end
    end

    if not icnsPath then
        if callback then callback(nil) end
        return
    end

    -- Ensure cache directory exists
    hs.fs.mkdir(self.iconCacheDir)

    -- Extract with sips (async)
    hs.task.new("/usr/bin/sips", function(exitCode, stdout, stderr)
        if exitCode == 0 then
            if callback then callback(iconPath) end
        else
            if callback then callback(nil) end
        end
    end, {"-s", "format", "png", icnsPath, "--out", iconPath}):start()
end

function obj:loadAppCache()
    -- Load cached app list from JSON file
    local file = io.open(self.appCacheFile, "r")
    if not file then return nil end

    local content = file:read("*a")
    file:close()

    local ok, data = pcall(hs.json.decode, content)
    if ok and data then
        return data
    end
    return nil
end

function obj:saveAppCache(apps)
    -- Save app list to JSON cache
    -- Ensure cache directory exists
    local cacheDir = self.appCacheFile:match("(.+)/[^/]+$")
    hs.fs.mkdir(cacheDir)

    local file = io.open(self.appCacheFile, "w")
    if file then
        file:write(hs.json.encode(apps))
        file:close()
    end
end

function obj:queryAppLastUsed(appPath, callback)
    -- Query last used date via mdls (async)
    hs.task.new("/usr/bin/mdls", function(exitCode, stdout, stderr)
        if exitCode ~= 0 then
            callback(nil)
            return
        end

        -- Parse output: "kMDItemLastUsedDate = YYYY-MM-DD HH:MM:SS +0000" or "(null)"
        if stdout:match("%(null%)") then
            callback(nil)
            return
        end

        local dateStr = stdout:match("= (.+)$")
        if dateStr then
            -- Parse to timestamp (simplified - just extract the date part)
            local y, m, d, H, M, S = dateStr:match("(%d+)-(%d+)-(%d+) (%d+):(%d+):(%d+)")
            if y then
                local timestamp = os.time({year=y, month=m, day=d, hour=H, min=M, sec=S})
                callback(timestamp)
                return
            end
        end
        callback(nil)
    end, {"-name", "kMDItemLastUsedDate", appPath}):start()
end

function obj:refreshAppRecency(apps, callback)
    -- Query last-used dates for all apps in parallel, then resort
    local pending = #apps
    if pending == 0 then
        if callback then callback(apps) end
        return
    end

    for i, app in ipairs(apps) do
        self:queryAppLastUsed(app.path, function(timestamp)
            apps[i].lastUsed = timestamp
            pending = pending - 1

            if pending == 0 then
                -- All queries complete, resort by recency
                table.sort(apps, function(a, b)
                    if a.lastUsed and b.lastUsed then
                        return a.lastUsed > b.lastUsed
                    elseif a.lastUsed then
                        return true
                    elseif b.lastUsed then
                        return false
                    else
                        return a.name:lower() < b.name:lower()
                    end
                end)

                -- Save updated cache
                self:saveAppCache(apps)

                if callback then callback(apps) end
            end
        end)
    end
end

function obj:handleMessage(msg)
    local body = msg.body
    self._logger.d("Message received:", hs.inspect(body))

    if body.type == "execute" then
        self:hide()
        local cmd = body.command
        if type(cmd) == "table" then
            -- Direct execution (list format) - run in background
            self._logger.i("Executing (direct):", cmd[1])
            hs.task.new(cmd[1], function() end, {}):start()
        else
            -- Check if command needs a terminal (interactive)
            local needsTerminal = cmd:match("^n?vim%s") or
                                  cmd:match("^v%s") or
                                  cmd:match("^v$") or
                                  cmd:match("&&%s*v$") or
                                  cmd:match("&&%s*v%s") or
                                  cmd:match("^htop") or
                                  cmd:match("^less%s") or
                                  cmd:match("^man%s") or
                                  cmd:match("^cmus") or
                                  cmd:match("^ytdl$") or
                                  cmd:match("^ytdl%s") or
                                  cmd:match("^emoji%-pick")

            if needsTerminal then
                -- Interactive command - open in Ghostty
                self._logger.i("Executing (terminal):", cmd)
                hs.task.new("/usr/bin/open", function() end, {
                    "-na", "ghostty",
                    "--args", "-e", "/opt/homebrew/bin/fish", "-c", cmd
                }):start()
            else
                -- Background shell command
                self._logger.i("Executing (shell):", cmd)
                hs.task.new("/opt/homebrew/bin/fish", function(exitCode, stdout, stderr)
                    -- Log output to file
                    local logDir = os.getenv("HOME") .. "/.log/hermes"
                    os.execute("mkdir -p " .. logDir)
                    local logFile = io.open(logDir .. "/latest.log", "a")
                    if logFile then
                        logFile:write("\n--- " .. os.date("%Y-%m-%d %H:%M:%S") .. " ---\n")
                        logFile:write("$ " .. cmd .. "\n")
                        logFile:write("exit: " .. tostring(exitCode) .. "\n\n")
                        if stdout and #stdout > 0 then logFile:write(stdout) end
                        if stderr and #stderr > 0 then logFile:write("\n--- stderr ---\n" .. stderr) end
                        logFile:close()
                    end
                    if exitCode ~= 0 then
                        self._logger.w("Command failed:", exitCode, stderr)
                        hs.notify.new({title = "Hermes", informativeText = "Command failed: " .. cmd}):send()
                    end
                end, {"-c", cmd}):start()
            end
        end

    elseif body.type == "close" then
        self:hide()

    elseif body.type == "reload" then
        -- Reload commands and send to UI
        self:loadCommands()
        local cmds = self:resolveCommands(self._commands)
        self._browser:evaluateJavaScript("HERMES.setCommands(" .. hs.json.encode(cmds) .. ")")

    elseif body.type == "log" then
        self._logger.i("[JS]", body.message)

    elseif body.type == "get_apps" then
        -- Load cached apps immediately, then refresh recency in background
        local apps = self:loadAppCache()
        if apps then
            -- Send cached data immediately
            self._browser:evaluateJavaScript("HERMES.setApps(" .. hs.json.encode(apps) .. ")")

            -- Refresh recency in background
            self:refreshAppRecency(apps, function(updatedApps)
                self._browser:evaluateJavaScript("HERMES.setApps(" .. hs.json.encode(updatedApps) .. ")")
            end)
        else
            -- No cache, scan fresh
            apps = self:scanApps()
            self._browser:evaluateJavaScript("HERMES.setApps(" .. hs.json.encode(apps) .. ")")

            -- Refresh recency and save to cache
            self:refreshAppRecency(apps, function(updatedApps)
                self._browser:evaluateJavaScript("HERMES.setApps(" .. hs.json.encode(updatedApps) .. ")")
            end)
        end

    elseif body.type == "launch_app" then
        self:hide()
        self._logger.i("Launching app:", body.appName)
        hs.task.new("/usr/bin/open", function() end, {"-a", body.appName}):start()

    elseif body.type == "extract_icon" then
        -- Extract icon for an app (async)
        self:extractAppIcon(body.appPath, body.appName, function(iconPath)
            if iconPath then
                self._browser:evaluateJavaScript(
                    "HERMES.updateAppIcon(" .. hs.json.encode(body.appName) .. ", " .. hs.json.encode(iconPath) .. ")"
                )
            end
        end)

    elseif body.type == "get_windows" then
        -- Query yabai for windows
        hs.task.new("/opt/homebrew/bin/yabai", function(exitCode, stdout, stderr)
            if exitCode ~= 0 then
                self._browser:evaluateJavaScript("HERMES.setWindows([])")
                return
            end

            local ok, windows = pcall(hs.json.decode, stdout)
            if not ok or not windows then
                self._browser:evaluateJavaScript("HERMES.setWindows([])")
                return
            end

            -- Filter and format windows
            local result = {}
            for _, win in ipairs(windows) do
                local isVisible = win["is-visible"]
                local isMinimized = win["is-minimized"]
                local title = win.title or ""

                if (isVisible or not isMinimized) and title ~= "" then
                    table.insert(result, {
                        id = win.id,
                        title = title,
                        app = win.app or "",
                        space = win.space or 0
                    })
                end
            end

            self._browser:evaluateJavaScript("HERMES.setWindows(" .. hs.json.encode(result) .. ")")
        end, {"-m", "query", "--windows"}):start()

    elseif body.type == "focus_window" then
        local windowId = math.floor(body.windowId)
        self:hide()

        -- Use synchronous execute for reliable focus
        hs.timer.doAfter(0.05, function()
            hs.execute("/opt/homebrew/bin/yabai -m window --focus " .. windowId)
        end)
    end
end

function obj:show()
    -- Show immediately with cached commands (empty on first launch)
    if self._cachedCommands then
        self._browser:evaluateJavaScript("HERMES.setCommands(" .. hs.json.encode(self._cachedCommands) .. ")")
    end
    self._browser:evaluateJavaScript("HERMES.reset()")
    self._browser:show()

    -- Focus the webview window
    local win = self._browser:hswindow()
    if win then
        win:focus()
    end

    -- Watch for clicks outside window
    self._clickWatcher = hs.eventtap.new({hs.eventtap.event.types.leftMouseDown}, function(e)
        local win = self._browser:hswindow()
        if win then
            local frame = win:frame()
            local pos = e:location()
            -- Check if click is outside the window frame
            if pos.x < frame.x or pos.x > frame.x + frame.w or
               pos.y < frame.y or pos.y > frame.y + frame.h then
                self:hide()
            end
        end
        return false
    end):start()

    -- Resolve fresh commands in background, then update UI
    hs.timer.doAfter(0, function()
        self:loadCommands()
        local cmds = self:resolveCommands(self._commands)
        self._cachedCommands = cmds
        self._browser:evaluateJavaScript("HERMES.setCommands(" .. hs.json.encode(cmds) .. ")")
    end)
end

function obj:hide()
    if self._clickWatcher then
        self._clickWatcher:stop()
        self._clickWatcher = nil
    end
    self._browser:hide()
end

function obj:showWindowMode()
    -- Enter window mode first, then show (avoid flash of main menu)
    self._browser:evaluateJavaScript("HERMES.enterWindowMode()")

    -- Small delay to let JS execute before showing
    hs.timer.doAfter(0.01, function()
        self._browser:show()

        local win = self._browser:hswindow()
        if win then
            win:focus()
        end

        -- Watch for clicks outside window
        self._clickWatcher = hs.eventtap.new({hs.eventtap.event.types.leftMouseDown}, function(e)
            local win = self._browser:hswindow()
            if win then
                local frame = win:frame()
                local pos = e:location()
                if pos.x < frame.x or pos.x > frame.x + frame.w or
                   pos.y < frame.y or pos.y > frame.y + frame.h then
                    self:hide()
                end
            end
            return false
        end):start()

        -- Load commands in background (for when user exits window mode)
        hs.timer.doAfter(0, function()
            self:loadCommands()
            local cmds = self:resolveCommands(self._commands)
            self._cachedCommands = cmds
            self._browser:evaluateJavaScript("HERMES.setCommands(" .. hs.json.encode(cmds) .. ")")
        end)
    end)
end

function obj:showAppMode()
    -- Enter app mode first, then show (avoid flash of main menu)
    self._browser:evaluateJavaScript("HERMES.enterAppMode()")

    -- Small delay to let JS execute before showing
    hs.timer.doAfter(0.01, function()
        self._browser:show()

        local win = self._browser:hswindow()
        if win then
            win:focus()
        end

        -- Watch for clicks outside window
        self._clickWatcher = hs.eventtap.new({hs.eventtap.event.types.leftMouseDown}, function(e)
            local win = self._browser:hswindow()
            if win then
                local frame = win:frame()
                local pos = e:location()
                if pos.x < frame.x or pos.x > frame.x + frame.w or
                   pos.y < frame.y or pos.y > frame.y + frame.h then
                    self:hide()
                end
            end
            return false
        end):start()

        -- Load commands in background (for when user exits app mode)
        hs.timer.doAfter(0, function()
            self:loadCommands()
            local cmds = self:resolveCommands(self._commands)
            self._cachedCommands = cmds
            self._browser:evaluateJavaScript("HERMES.setCommands(" .. hs.json.encode(cmds) .. ")")
        end)
    end)
end

function obj:toggle()
    local win = self._browser:hswindow()
    if win and win:isVisible() then
        self:hide()
    else
        self:show()
    end
end

function obj:stop()
    if self._hotkey then
        self._hotkey:delete()
        self._hotkey = nil
    end
    if self._browser then
        self._browser:delete()
        self._browser = nil
    end
    self._logger.i("Hermes stopped")
end

return obj
