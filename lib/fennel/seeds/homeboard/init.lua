local durp = require("lib/durationpicker")
local wake = require("lib/wakeDialog")

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

function obj:evalJS(method, args)
    obj._logger.df("HOMEBOARD.%s(...)", method)
    obj.browser:evaluateJavaScript("HOMEBOARD."..method.."("..args..")")
end

function obj:addTodos()
    for name, path in pairs(obj.todosPaths) do
        local text = io.open(path, "r"):read("*all")
        obj:evalJS("addTodos", "'"..name.."', ".. hs.inspect(text))
    end
end

function obj:videoToPlay()
    return obj.videos[math.random(#obj.videos)]
end

function obj:addBoard()
    for file in hs.execute("ls "..obj.homeBoardPath.."/board/*"):gmatch("[^\n]+") do
        local text = io.open(file, "r"):read("*all")
        local fileName = file:match("^.+/([^%.]+).+$")
        obj:evalJS("addBoardItem", "'"..fileName.."', "..hs.inspect(text))
    end
end

function obj:addMusings()
    for file in hs.execute("ls "..obj.homeBoardPath.."/musings/*"):gmatch("[^\n]+") do
        local text = io.open(file, "r"):read("*all")
        obj:evalJS("addMusing", hs.inspect(text))
    end
end

function obj:setReview()
    local lastPlan = obj:getLastPlan()
    obj:evalJS("setReview", hs.inspect(obj:getLastPlanTime())..","..hs.inspect(lastPlan))
end

function handleHomeboardMessages(response)
    local body = response.body
    obj._logger.df("homeboard msg type: %s", body.type)
    if body.type == "journal/loaded" then
        obj:setReview()
    elseif body.type == "plan/loaded" then
        obj:setReview()
        obj:addTodos()
        obj:addBoard()
    elseif body.type == "muse/loaded" then
        obj:evalJS("showVideo", "\"file://"..obj:videoToPlay().."\"")
        obj:addMusings()
        obj:evalJS("shuffleMusings", "")
    elseif body.type == "muse/newVideo" then
        obj:evalJS("showVideo", "\"file://"..obj:videoToPlay().."\"")
    elseif body.type == "muse/pickVideo" then
        pickedVideo = hs.dialog.chooseFileOrFolder("Pick a video to play:", obj.videosPath)
        if pickedVideo then
            obj:evalJS("showVideo", "\"file://"..pickedVideo["1"].."\"")
        end
    elseif body.type == "submit/journal" then
        obj._journal = body.value
    elseif body.type == "submit/plan" then
        obj._plan = body.value
    elseif body.type == "submit/done" then
        local date = hs.execute("printf '%s' `date +%y-%m-%d_%H:%M`")
        if obj._journal then
            io.open(obj.homeBoardPath.."journals/"..date..".journal.txt", "w")
            :write(obj._journal)
            :close()
        end
        if obj._plan then
            io.open(obj.homeBoardPath.."plans/"..date..".plan.txt", "w")
            :write(obj._plan)
            :close()
        end
        obj.browser:delete()
    else
        hs.printf("Unknown HomeBoard Response: %s", hs.inspect(body))
    end
end

function obj:showHomeBoard(onClose)
    local jsPortName = "HammerSpoon" -- NOTE: used by homeboard.js
    local uc = hs.webview.usercontent.new(jsPortName)
    uc:setCallback(handleHomeboardMessages)
    local frame = hs.screen.primaryScreen():fullFrame()
    local rect = hs.geometry.rect(
        frame["x"] + (1 * frame["w"] / 16),
        frame["y"] + (1 * frame["h"] / 16),
        14 * frame["w"] / 16,
        14 * frame["h"] / 16)
    local browser = hs.webview.newBrowser(rect, {developerExtrasEnabled = true}, uc)
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
    local f = "file://"..obj.homeBoardPath.."/journal.html"
    browser:url(f):show()
    browser:hswindow():focus()
    obj.browser = browser
    return browser
end

function obj:snoozeTimer(duration)
    obj._minutesLeft = duration
    obj._state = "countdown"
    obj:renderMenuBar()
end

function obj:pickSnooze()
    local onClose = (obj._minutesLeft < 5) and obj.pickSnooze or function() obj:snoozeTimer(obj._minutesLeft) end
    durp:show({
        defaultDuration = obj.defaultDuration or 180,
        onDuration = function(duration) obj:snoozeTimer(duration) end,
        onClose = onClose
    })
end

function obj:renderMenuBar()
    obj._menubar:setIcon(obj.spoonPath.."/home.png")
    obj._menubar:setTitle(obj._state == "sleeping" and "zzz" or math.ceil(obj._minutesLeft or 0))
end

function obj:notifCallback()
    if obj._state ~= "active" then
        obj._state = "active"
        obj:showHomeBoard(function()
            obj:pickSnooze()
        end)
    end
end

function obj:ensureNotifDelivered()
    if not hs.fnutils.contains(hs.notify.deliveredNotifications(), obj._notif) then
        if obj._notif:activationType() == hs.notify.activationTypes.none then
            obj._state = "countdown"
        end
    end
end

function obj:heartbeat()
    obj._logger.df("HeartBeat state = %s, ", obj._state)
    if obj._state == "countdown" then
        obj._minutesLeft = obj._minutesLeft - 1
        if obj._minutesLeft <= 0 then
            obj._state = "notif"
            obj._notif:send()
        end
    elseif obj._state == "notif" then
        obj:ensureNotifDelivered()
    elseif obj._state == "active" then
    elseif obj._state == "sleeping" then
    else
        obj._logger.ef("UNEXPECTED STATE: %s", hs.inspect(obj._state))
    end
    obj:renderMenuBar()
end

function onWake()
    obj._logger.df("systemDidWake -> %s", obj._prevState)
    obj._state = (obj._prevState or obj._state)
    obj._prevState = nil
    obj:renderMenuBar()
end


function onSleep()
    obj._logger.df("systemWillSleep <- %s", obj._state)
    obj._prevState = (obj._state ~= "sleeping" and obj._state or obj._prevState)
    obj._state = "sleeping"
    obj:renderMenuBar()
end

function obj:start(config)
    obj._logger = hs.logger.new("HomeBoard", "debug")
    for k,v in pairs(config) do obj[k] = v end
    obj.videos = {}
    for line in hs.execute("find "..obj.videosPath.." -type f -not -path '*/\\.*'"):gmatch("[^\n]+") do
        table.insert(obj.videos, line)
    end
    local notification = {title = "Set the homeboard timer!", withdrawAfter = 0}
    obj._notif = hs.notify.new(obj.notifCallback, notification)
    obj._menubar = hs.menubar.new()
    obj._menubar:setClickCallback(obj.notifCallback)
    obj._state = "countdown"
    obj._minutesLeft = 180
    obj:renderMenuBar()
    obj._heartbeat = hs.timer.doEvery(60, obj.heartbeat)
    wake:onSleep(onSleep):onWake(onWake):start()
end

function obj:stop()
    obj._menubar:delete()
    if obj._notif then
        obj._notif:withdraw()
    end
    obj._heartbeat:stop()
    return self
end

return obj
