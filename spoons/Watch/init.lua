local obj = {}

obj.name = "Watch"
obj.version = "1.0"
obj.author = "Anthony D'Ambrosio <anthony.dayzerostudio@gmail.com>"
obj.homepage = "https://github.com/pancia/dotfiles/tree/master/spoons/watch"
obj.license = "MIT - https://opensource.org/licenses/MIT"
obj.attributions = {
    "Watch icon made by: https://www.flaticon.com/free-icon/clock_2088617",
}

local function script_path()
    local str = debug.getinfo(2, "S").source:sub(2)
    return str:match("(.*/)")
end
obj.spoonPath = script_path()

obj.scripts = {}
obj.interval = 60

function obj:init()
end

function runScriptCmd(script)
    cmd = script.command
    hs.execute("mkdir -p "..obj.logDir)
    local logFileLoc = obj.logDir.."/"..script.name
    hs.execute(cmd.." | tee -a "..logFileLoc.." &", true)
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
    hs.execute("open -a TextEdit '"..logFileLoc.."'", true)
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

function obj:start()
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
    local menu = renderMenu()
    obj._menubar = hs.menubar.new():setMenu(renderMenu)
    renderMenuBar()
    return self
end

function obj:stop()
    hs.fnutils.ieach(obj.scripts, function(script)
        script._timer:stop()
        script._delayedStartTimer:stop()
    end)
    return self
end

return obj
