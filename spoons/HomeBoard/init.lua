local obj = {}

obj.name = "HomeBoard"
obj.version = "1.0"
obj.author = "Anthony D'Ambrosio <anthony.dayzerostudio@gmail.com>"
obj.homepage = "https://github.com/pancia/dotfiles/tree/master/spoons/homeboard"
obj.license = "MIT - https://opensource.org/licenses/MIT"

function obj:init() end

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
    for line in hs.execute("find ~/Movies/HomeBoard/ -type f -not -path '*/\\.*'"):gmatch("[^\n]+") do
        table.insert(files, line)
    end
    videoToPlay = function() return files[math.random(#files)] end
    uc:setCallback(function(response)
        local body = response.body
        if body.type == "loaded" then
            browser:evaluateJavaScript("HOMEBOARD.showVideo(\"file://"..videoToPlay().."\")")
            local lastPlanFile = hs.execute("printf '%s' $(ls -t "..obj.homeBoardPath.."/*.plan.txt 2> /dev/null | head -n 1)")
            if lastPlanFile and not lastPlanFile == '' then
                local lastPlan = io.open(lastPlanFile, "r"):read("*all")
                browser:evaluateJavaScript("HOMEBOARD.setReview(".. hs.inspect(lastPlan) ..")")
            end
        elseif body.type == "newVideo" then
            browser:evaluateJavaScript("HOMEBOARD.showVideo(\"file://"..videoToPlay().."\")")
        elseif body.type == "done" then
            browser:delete()
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
    browser:url(f):bringToFront():show()
    return browser
end

function obj:start()
    obj._menubar = hs.menubar.new()
    obj._menubar:setClickCallback(obj.showHomeBoard)
    obj._menubar:setTitle("HomeBoard")
end

function obj:stop()
    obj._menubar:delete()
    return self
end

return obj
