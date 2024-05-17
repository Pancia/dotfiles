local obj = {}

obj.spoonPath = os.getenv("HOME").."/dotfiles/lib/lua/seeds/homeboard/"

function obj:init() end

function obj:evalJS(method, args)
    obj._logger.df("HOMEBOARD.%s(...)", method)
    obj.browser:evaluateJavaScript("HOMEBOARD."..method.."("..args..")")
end

function obj:videoToPlay()
    return obj.videos[math.random(#obj.videos)]
end

function obj:addBoard()
    for file in hs.execute("ls "..obj.homeBoardPath.."/board/*"):gmatch("[^\n]+") do
        if file:match(".link$") then
            local text = io.open(file, "r"):read("*all")
            local fileName = file:match("^.+/([^%.]+).+$")
            obj:evalJS("addBoardLink", "'"..fileName.."', "..hs.inspect(text))
        else
            local text = io.open(file, "r"):read("*all")
            local fileName = file:match("^.+/([^%.]+).+$")
            obj:evalJS("addBoardItem", "'"..fileName.."', "..hs.inspect(text))
        end
    end
end

function obj:addMusings()
    for file in hs.execute("ls "..obj.homeBoardPath.."/musings/*"):gmatch("[^\n]+") do
        local text = io.open(file, "r"):read("*all")
        obj:evalJS("addMusing", hs.inspect(text))
    end
end

function handleHomeboardMessages(response)
    local body = response.body
    obj._logger.df("homeboard msg type: %s", body.type)
    if body.type == "muse/loaded" then
        obj:evalJS("showVideo", "\"file://"..obj:videoToPlay().."\"")
        obj:addMusings()
        obj:addBoard()
        obj:evalJS("shuffleMusings", "")
    elseif body.type == "muse/newVideo" then
        obj:evalJS("showVideo", "\"file://"..obj:videoToPlay().."\"")
    elseif body.type == "muse/pickVideo" then
        pickedVideo = hs.dialog.chooseFileOrFolder("Pick a video to play:", obj.videosPath)
        if pickedVideo then
            obj:evalJS("showVideo", "\"file://"..pickedVideo["1"].."\"")
        end
    else
        hs.printf("Unknown HomeBoard Response: %s", hs.inspect(body))
    end
end

function obj:showHomeBoard()
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
            obj.browser = nil
        end
    end)
    browser:deleteOnClose(true)
    browser:transparent(true)
    local f = "file://"..obj.homeBoardPath.."/muse.html"
    browser:url(f):show()
    browser:hswindow():focus()
    obj.browser = browser
    return browser
end

function obj:start(config)
    for k,v in pairs(config) do obj[k] = v end
    obj._logger = hs.logger.new("HomeBoard", "debug")
    obj.videos = {}
    for line in hs.execute("find "..obj.videosPath.." -type f -not -path '*/\\.*'"):gmatch("[^\n]+") do
        table.insert(obj.videos, line)
    end
    obj._menubar = hs.menubar.new()
    obj._menubar:setClickCallback(obj.showHomeBoard)

    print(obj.spoonPath.."/home.png")
    obj._menubar:setIcon(obj.spoonPath.."/home.png")
    return self
end

function obj:stop()
    obj._menubar:delete()
    return self
end

return obj
