local obj = {}

obj.name = "HomeBoard"
obj.version = "1.0"
obj.author = "Anthony D'Ambrosio <anthony.dayzerostudio@gmail.com>"
obj.homepage = "https://github.com/pancia/dotfiles/tree/master/spoons/homeboard"
obj.license = "MIT - https://opensource.org/licenses/MIT"
obj.attributions = {
    "Home icon from: https://www.flaticon.com/free-icon/home_553376"
}

obj.spoonPath = hs.spoons.scriptPath()

function obj:init() end

function getLastPlanFile()
    return hs.execute("printf '%s' $(ls -t "..obj.homeBoardPath.."/plans/*.plan.txt 2> /dev/null | head -n 1)")
end

function obj:getLastPlan()
    local lastPlanFile = getLastPlanFile()
    hs.printf("lastPlanFile: %s", hs.inspect(lastPlanFile))
    if lastPlanFile and lastPlanFile ~= '' then
        return io.open(lastPlanFile, "r"):read("*all")
    end
end

-- NOTE: used to make notif subtitle
function obj:getLastPlanTime()
    local lastPlanFile = getLastPlanFile()
    if lastPlanFile and lastPlanFile ~= '' then
        return lastPlanFile:match("[%d-:_]+")
    else
        return ""
    end
end

function obj:addTodos()
    for name, path in pairs(obj.todosPaths) do
        local text = io.open(path, "r"):read("*all")
        obj.browser:evaluateJavaScript("HOMEBOARD.addTodos('"..name.."', ".. hs.inspect(text) ..")")
    end
end

function obj:videoToPlay()
    return obj.files[math.random(#obj.files)]
end

function obj:addBoard()
    for file in hs.execute("ls "..obj.homeBoardPath.."/"..obj.boardFolder.."/*"):gmatch("[^\n]+") do
        local text = io.open(file, "r"):read("*all")
        local fileName = file:match("^.+/([^%.]+).+$")
        obj.browser:evaluateJavaScript("HOMEBOARD.addBoardItem('"..fileName.."', "..hs.inspect(text)..")")
    end
end

function obj:addMusings()
    for file in hs.execute("ls "..obj.homeBoardPath.."/"..obj.musingsFolder.."/*"):gmatch("[^\n]+") do
        local text = io.open(file, "r"):read("*all")
        obj.browser:evaluateJavaScript("HOMEBOARD.addMusing("..hs.inspect(text)..")")
    end
end

function handleHomeboardMessages(response)
    local body = response.body
    if body.type == "loaded" then
        obj.browser:evaluateJavaScript("HOMEBOARD.showVideo(\"file://"..obj:videoToPlay().."\")")
        local lastPlan = obj:getLastPlan()
        obj.browser:evaluateJavaScript("HOMEBOARD.setReview("..hs.inspect(obj:getLastPlanTime())..","..hs.inspect(lastPlan)..")")
        obj:addTodos()
        obj:addBoard()
        obj:addMusings()
        obj.browser:evaluateJavaScript("HOMEBOARD.doneLoading()")
    elseif body.type == "newVideo" then
        obj.browser:evaluateJavaScript("HOMEBOARD.showVideo(\"file://"..obj:videoToPlay().."\")")
    elseif body.type == "pickVideo" then
        pickedVideo = hs.dialog.chooseFileOrFolder("Pick a video to play:", obj.videosPath)
        if pickedVideo then
            obj.browser:evaluateJavaScript("HOMEBOARD.showVideo(\"file://"..pickedVideo["1"].."\")")
        end
    elseif body.type == "journal" then
        local journal = hs.execute("printf '%s' `date +%y-%m-%d_%H:%M`")
        io.open(obj.homeBoardPath.."journals/"..journal..".journal.txt", "w")
        :write(body.value)
        :close()
    elseif body.type == "plan" then
        local plan = hs.execute("printf '%s' `date +%y-%m-%d_%H:%M`")
        io.open(obj.homeBoardPath.."plans/"..plan..".plan.txt", "w")
        :write(body.value)
        :close()
    elseif body.type == "done" then
        obj.browser:delete()
    else
        hs.printf("Unknown HomeBoard Response: %s", hs.inspect(body))
    end
end

function obj:showHomeBoard(onClose)
    local jsPortName = "HammerSpoon" -- NOTE: used by homeboard.js
    local uc = hs.webview.usercontent.new(jsPortName)
    uc:setCallback(handleHomeboardMessages)
    local fullscreen = hs.screen.primaryScreen():fullFrame()
    local browser = hs.webview.newBrowser(fullscreen, {developerExtrasEnabled = true}, uc)
    browser:windowCallback(function(action, webview)
        if action == "closing" then
            if onClose then onClose() end
        end
    end)
    browser:deleteOnClose(true)
    browser:transparent(true)
    local f = "file://"..obj.homeBoardPath.."/index.html"
    browser:url(f):show()
    browser:hswindow():focus()
    obj.browser = browser
    return browser
end

function obj:start()
    obj._menubar = hs.menubar.new()
    obj._menubar:setClickCallback(obj.showHomeBoard)
    obj._menubar:setIcon(obj.spoonPath.."/home.png")
    obj.files = {}
    for line in hs.execute("find "..obj.videosPath.." -type f -not -path '*/\\.*'"):gmatch("[^\n]+") do
        table.insert(obj.files, line)
    end
end

function obj:stop()
    obj._menubar:delete()
    return self
end

return obj
