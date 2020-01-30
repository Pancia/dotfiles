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

obj.interval = 15 -- seconds
obj.triggerEvery = 2 -- * interval ~> 30 seconds
obj.scripts = {}

function obj:init()
    obj._timerCounter = 0
end

function watchBlock()
    if obj._timerCounter == 0 then
        hs.fnutils.ieach(obj.scripts, function(script)
            cmd = script.command
            local output, status, exit_type, exit_code = hs.execute(cmd, true)
            if exit_code ~= 0 then
                hs.printf("Watch(%s) -> %s:\n%s", cmd, exit_code, output)
            end
        end)
    end
    obj._timerCounter = (obj._timerCounter - 1) % obj.triggerEvery
end

function obj:start()
    watchBlock()
    obj._timerCounter = obj.triggerEvery
    obj._watchTimer = hs.timer.doEvery(obj.interval, watchBlock)
    return self
end

function obj:stop()
    obj._watchTimer:stop()
    return self
end

return obj
