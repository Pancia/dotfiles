local durp = require("lib/durationpicker")

local obj = {}

obj.spoonPath = os.getenv("HOME").."/dotfiles/lib/fennel/seeds/homeboard/"

function obj:init() end

function obj:getLastPlanFile()
    return hs.execute("printf '%s' $(ls -t "..obj.homeBoardPath.."/plans/*.plan.txt 2> /dev/null | head -n 1)")
end

function obj:getLastPlan()
    local lastPlanFile = obj:getLastPlanFile()
    hs.printf("lastPlanFile: %s", hs.inspect(lastPlanFile))
    if lastPlanFile and lastPlanFile ~= '' then
        return io.open(lastPlanFile, "r"):read("*all")
    end
end

-- NOTE: used to make notif subtitle
function obj:getLastPlanTime()
    local lastPlanFile = obj:getLastPlanFile()
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
    return obj.videos[math.random(#obj.videos)]
end

function obj:addBoard()
    for file in hs.execute("ls "..obj.homeBoardPath.."/board/*"):gmatch("[^\n]+") do
        local text = io.open(file, "r"):read("*all")
        local fileName = file:match("^.+/([^%.]+).+$")
        obj.browser:evaluateJavaScript("HOMEBOARD.addBoardItem('"..fileName.."', "..hs.inspect(text)..")")
    end
end

function obj:addMusings()
    for file in hs.execute("ls "..obj.homeBoardPath.."/musings/*"):gmatch("[^\n]+") do
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
            if onClose then
              onClose()
              obj.browser = nil
            end
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

function obj:snoozeTimer(duration)
    obj._ensureTimer = obj._ensureTimer:stop()
    obj._boardTimer = hs.timer.doAfter(60*duration, function()
        obj._boardTimer = nil
        obj._ensureTimer = obj._ensureTimer:setNextTrigger(0)
    end)
    obj._menuRefreshTimer:fire()
end

function obj:pickSnooze()
    obj._ensureTimer = obj._ensureTimer:stop()
    durp:show({
        defaultDuration = obj.defaultDuration or 180,
        onDuration = function(duration) obj:snoozeTimer(duration) end,
        onClose = obj.pickSnooze,
    })
end

function obj:renderMenuBar()
    obj._menubar:setClickCallback(obj.showHomeBoard)
    obj._menubar:setIcon(obj.spoonPath.."/home.png")
    local nextTrigger = (obj._boardTimer and obj._boardTimer:nextTrigger()) or 0
    local title = math.max(math.ceil(nextTrigger / 60), 0)
    obj._menubar:setTitle(title)
end

function obj:notifCallback()
    obj:showHomeBoard(function()
        obj:pickSnooze()
    end)
end

function obj:ensureTimer()
    if not obj._clearCheck and not obj.browser then
        obj._notif:send()
        obj._clearCheck = hs.timer.doEvery(1, function()
            if not hs.fnutils.contains(hs.notify.deliveredNotifications(), obj._notif) then
                if obj._notif:activationType() == hs.notify.activationTypes.none then
                    obj:notifCallback()
                end
                if obj._clearCheck then
                    obj._clearCheck:stop()
                    obj._clearCheck = nil
                end
            end
        end)
    end
end

function obj:start(config)
    for k,v in pairs(config) do obj[k] = v end
    obj.videos = {}
    for line in hs.execute("find "..obj.videosPath.." -type f -not -path '*/\\.*'"):gmatch("[^\n]+") do
        table.insert(obj.videos, line)
    end
    local notification = {title = "Set the homeboard timer!", withdrawAfter = 0}
    obj._notif = hs.notify.new(obj.notifCallback, notification)
    obj._menubar = hs.menubar.new()
    obj:renderMenuBar()
    obj._menuRefreshTimer = hs.timer.doEvery(60, obj.renderMenuBar)
    obj._ensureTimer = hs.timer.doEvery(60, obj.ensureTimer):setNextTrigger(0)
end

function obj:stop()
    obj._menubar:delete()
    if obj._notif then
        obj._notif:withdraw()
    end
    return self
end

return obj
