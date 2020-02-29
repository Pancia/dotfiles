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
    local now = hs.execute("date +%X_%x")
    hs.execute("mkdir -p "..obj.logDir)
    local logFileLoc = obj.logDir.."/"..script.name
    local logFile = io.open(logFileLoc, "a")
    logFile:write(string.format("`%s` @ [%s]: {\n", cmd, now:gsub("\n$", "")))
    local _, _, _, exit_code = hs.execute(cmd.." | tee -a "..logFileLoc, true)
    logFile:write(string.format("\n} -> %s\n", exit_code))
    logFile:close()
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

function scriptToHtml(script)
    local logFile = io.open(obj.logDir.."/"..script.name, "r")
    local log = logFile:read("*all")
    logFile:close()
    return "<html>"
        .. "<script>window.onload = () => window.scrollTo(0,document.body.scrollHeight);</script>"
        .. "<body style='background-color:rgba(240, 240, 240, 1)'>"
        .. "<pre>" .. log .. "</pre>"
        .. "</body>"
        .. "</html>"
end

function viewScriptLogFile(script)
    local frame = hs.screen.primaryScreen():fullFrame()
    webviewRect = hs.geometry.rect(
        frame["x"] + (frame["w"] / 3),
        frame["y"] + (frame["h"] / 4),
        frame["w"] / 3,
        frame["h"] / 2)
    hs.webview.newBrowser(webviewRect)
        :html(scriptToHtml(script))
        :bringToFront(true)
        :shadow(true)
        :show()
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
                runScriptCmd(script)
                viewScriptLogFile(script)
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
