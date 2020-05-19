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

function obj:getLastPlan()
    local lastPlanFile = hs.execute("printf '%s' $(ls -t "..obj.homeBoardPath.."/*.plan.txt 2> /dev/null | head -n 1)")
    hs.printf("lastPlanFile: %s", hs.inspect(lastPlanFile))
    if lastPlanFile and lastPlanFile ~= '' then
        return io.open(lastPlanFile, "r"):read("*all")
    end
end

function obj:showHomeBoard(onClose)
    local frame = hs.screen.primaryScreen():fullFrame()
    local rect = hs.geometry.rect(
    frame["x"] + 1 * (frame["w"] / 8),
    frame["y"] + 0 * (frame["h"] / 8),
    3 * frame["w"] / 4,
    4 * frame["h"] / 4)
    local uc = hs.webview.usercontent.new("HammerSpoon") -- jsPortName
    local browser
    files = {}
    for line in hs.execute("find "..obj.videosPath.." -type f -not -path '*/\\.*'"):gmatch("[^\n]+") do
        table.insert(files, line)
    end
    videoToPlay = function() return files[math.random(#files)] end
    uc:setCallback(function(response)
        local body = response.body
        if body.type == "loaded" then
            browser:evaluateJavaScript("HOMEBOARD.showVideo(\"file://"..videoToPlay().."\")")
            local lastPlan = obj:getLastPlan()
            browser:evaluateJavaScript("HOMEBOARD.setReview(".. hs.inspect(lastPlan) ..")")
        elseif body.type == "newVideo" then
            browser:evaluateJavaScript("HOMEBOARD.showVideo(\"file://"..videoToPlay().."\")")
        elseif body.type == "pickVideo" then
            pickedVideo = hs.dialog.chooseFileOrFolder("Pick a video to play:", obj.videosPath)
            if pickedVideo then
                browser:evaluateJavaScript("HOMEBOARD.showVideo(\"file://"..pickedVideo["1"].."\")")
            end
        elseif body.type == "journal" then
            local journal = hs.execute("printf '%s' `date +%y-%m-%d_%H:%M`")
            io.open(obj.homeBoardPath..journal..".journal.txt", "w")
            :write(body.value)
            :close()
        elseif body.type == "plan" then
            local plan = hs.execute("printf '%s' `date +%y-%m-%d_%H:%M`")
            io.open(obj.homeBoardPath..plan..".plan.txt", "w")
            :write(body.value)
            :close()
        elseif body.type == "done" then
            browser:delete()
        else
            hs.printf("Unknown HomeBoard Response: %s", hs.inspect(body))
        end
    end)
    browser = hs.webview.newBrowser(rect, {developerExtrasEnabled = true}, uc)
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
    return browser
end

function obj:start()
    obj._menubar = hs.menubar.new()
    obj._menubar:setClickCallback(obj.showHomeBoard)
    obj._menubar:setIcon(obj.spoonPath.."/home.png")
end

function obj:stop()
    obj._menubar:delete()
    return self
end

return obj
