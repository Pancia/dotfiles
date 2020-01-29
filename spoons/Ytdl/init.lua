local obj = {}

obj.name = "YTDL"
obj.version = "1.0"
obj.author = "Anthony D'Ambrosio <anthony.dayzerostudio@gmail.com>"
obj.homepage = "https://github.com/pancia/dotfiles/tree/master/spoons/ytdl"
obj.license = "MIT - https://opensource.org/licenses/MIT"

local function script_path()
    local str = debug.getinfo(2, "S").source:sub(2)
    return str:match("(.*/)")
end
obj.spoonPath = script_path()

obj.interval = 15 -- seconds
obj.triggerEvery = 2 -- * interval ~> 30 seconds

function obj:init()
    obj._timerCounter = 0
end

function ytdlBlock()
    if obj._timerCounter == 0 then
        cmd = obj.spoonPath.."/ytdl.sh "
        local output, status, exit_type, exit_code = hs.execute(cmd, true)
        if exit_code ~= 0 then
            hs.printf("YTDL(%s):\n%s", exit_code, output)
        end
    end
    obj._timerCounter = (obj._timerCounter - 1) % obj.triggerEvery
end

function obj:start()
    ytdlBlock()
    obj._timerCounter = obj.triggerEvery
    obj._ytdlTimer = hs.timer.doEvery(obj.interval, ytdlBlock)
    return self
end

function obj:stop()
    obj._ytdlTimer:stop()
    return self
end

return obj
