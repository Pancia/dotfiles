local menubarRegistry = require("lib/menubarRegistry")

local obj = {}

obj.spoonPath = os.getenv("HOME").."/dotfiles/lib/lua/seeds/watch/"

obj.scripts = {}
obj.interval = 60

function obj:init()
end

function runScriptCmd(script)
    hs.execute("mkdir -p "..obj.logDir)
    local logFileLoc = obj.logDir.."/"..script.name
    hs.task.new(script.command, nil, function(_, stdOut, stdErr)
        io.open(logFileLoc, "a"):write(stdOut):write(stdErr):close()
        return true
    end):start()
end

function startScriptTimer(script)
    script._timer = hs.timer.doEvery(obj.interval * script.triggerEvery, function()
        runScriptCmd(script)
    end)
end

function renderMenuBar()
    obj._menubar:setIcon(obj.spoonPath.."/watch.png")
end

function scriptTitle(script)
    local timer = script._delayedStartTimer or script._timer
    local next = timer:nextTrigger()
    return math.floor(next) .. " -> " .. script.command
end

function viewScriptLogFile(script)
    local logFileLoc = obj.logDir.."/"..script.name
    hs.osascript.applescript("tell application \"iterm2\""
    .."\ncreate window with default profile command \"fish -c 'viewLog "..logFileLoc.."'\""
    .."\nend tell")
end

function renderMenu()
    return hs.fnutils.mapCat(obj.scripts, function(script)
        return {
            {title = scriptTitle(script)},
            {title = "-> View Log File"
            , fn = function()
                viewScriptLogFile(script)
            end},
            {title = "-> Execute now!"
            , fn = function()
                viewScriptLogFile(script)
                runScriptCmd(script)
            end},
            {title = "-"},
        }
    end)
end

function obj:start(config)
    for k,v in pairs(config) do obj[k] = v end
    hs.fnutils.ieach(obj.scripts, function(script)
        if type(script.delayStart) == "number" then
            if script.delayStart == 0 then
                runScriptCmd(script)
                startScriptTimer(script)
            else
                script._delayedStartTimer = hs.timer.doAfter(obj.interval * script.delayStart, function()
                    script._delayedStartTimer = nil
                    startScriptTimer(script)
                    runScriptCmd(script)
                end)
            end
        else
            startScriptTimer(script)
        end
    end)

    -- Get or create persistent menubar (survives soft reloads)
    local mb, isNew = menubarRegistry.getOrCreate("watch")
    obj._menubar = mb

    -- Always update menu callback (points to new code after reload)
    obj._menubar:setMenu(renderMenu)
    renderMenuBar()
    return self
end

-- Soft stop: cleanup resources but preserve menubar (for soft reload)
function obj:softStop()
    hs.fnutils.ieach(obj.scripts, function(script)
        if script._timer then
            script._timer:stop()
        end
        if script._delayedStartTimer then
            script._delayedStartTimer:stop()
        end
    end)
    -- NOTE: Do NOT delete menubar - it persists across soft reloads
    obj._menubar = nil
    return self
end

-- Hard stop: full cleanup including menubar (for hard reload)
function obj:stop()
    obj:softStop()
    menubarRegistry.delete("watch")
    return self
end

return obj
