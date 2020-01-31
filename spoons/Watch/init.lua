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

function watchBlock(script)
    return function()
        if script._timerCounter == 0 then
            cmd = script.command
            local output, status, exit_type, exit_code = hs.execute(cmd, true)
            if exit_code ~= 0 then
                hs.printf("Watch(%s) -> %s:\n%s", cmd, exit_code, output)
            end
        end
        script._timerCounter = (script._timerCounter - 1) % script.triggerEvery
    end
end

function obj:start()
    hs.fnutils.ieach(obj.scripts, function(script)
        script._timerCounter = 0
        if script.runOnStart == true then
            watchBlock(script)()
        end
        script._timerCounter = script.triggerEvery
        script._watchTimer = hs.timer.doEvery(script.interval, watchBlock(script))
    end)
    return self
end

function obj:stop()
    obj._watchTimer:stop()
    return self
end

return obj
