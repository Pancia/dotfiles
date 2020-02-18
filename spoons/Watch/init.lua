local obj = {}

obj.name = "Watch"
obj.version = "1.0"
obj.author = "Anthony D'Ambrosio <anthony.dayzerostudio@gmail.com>"
obj.homepage = "https://github.com/pancia/dotfiles/tree/master/spoons/watch"
obj.license = "MIT - https://opensource.org/licenses/MIT"

local function script_path()
    local str = debug.getinfo(2, "S").source:sub(2)
    return str:match("(.*/)")
end
obj.spoonPath = script_path()

obj.scripts = {}

function obj:init()
end

function runScriptCmd(script)
    cmd = script.command
    local output, status, exit_type, exit_code = hs.execute(cmd, true)
    if exit_code ~= 0 then
        hs.printf("Watch(%s) -> %s:\n%s", cmd, exit_code, output)
    end
end

function scriptBlock(script)
    if script._timerCounter == 0 then
        runScriptCmd(script)
    end
    script._timerCounter = (script._timerCounter - 1) % script.triggerEvery
end

function startScriptTimer(script)
    script._timerCounter = 0
    script._timerCounter = script.triggerEvery
    script._watchTimer = hs.timer.doEvery(script.interval, function()
        scriptBlock(script)
    end)
end

function obj:start()
    hs.fnutils.ieach(obj.scripts, function(script)
        if type(script.delayStart) == "number" then
            if script.delayStart == 0 then
                runScriptCmd(script)
                startScriptTimer(script)
            else
                script._delayedStartTimer = hs.timer.doAfter(script.interval * script.delayStart, function()
                    startScriptTimer(script)
                    runScriptCmd(script)
                end)
            end
        else
            startScriptTimer(script)
        end
    end)
    return self
end

function obj:stop()
    hs.fnutils.ieach(obj.scripts, function(script)
        script._watchTimer:stop()
        script._delayedStartTimer:stop()
    end)
    return self
end

return obj
