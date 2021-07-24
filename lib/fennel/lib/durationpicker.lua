local obj = {}

local lib = os.getenv("HOME").."/dotfiles/lib/fennel/lib"

local width = 640
local height = 320

function obj:show(opts)
    local frame = hs.screen.primaryScreen():fullFrame()
    local rect = hs.geometry.rect(
    frame["x"] + (frame["w"] / 2) - (width / 2),
    frame["y"] + (frame["h"] / 2) - (height / 2),
    width, height)
    local uc = hs.webview.usercontent.new("HammerSpoon") -- jsPortName
    local browser
    local pickedDuration = false
    uc:setCallback(function(response)
        if response.body.onload then
            if opts.defaultDuration then
                browser:evaluateJavaScript("PICKER.setDuration("..opts.defaultDuration..")")
            end
        elseif response.body.duration then
            local duration = response.body.duration
            pickedDuration = true
            browser:delete()
            opts.onDuration(duration)
        end
    end)
    browser = hs.webview.newBrowser(rect, {developerExtrasEnabled = true}, uc)
    browser:windowCallback(function(action, webview)
        if action == "closing" and not pickedDuration then
            if opts.onClose then opts.onClose(duration) end
        end
    end)
    browser:deleteOnClose(true)
    local f = io.open(lib.."/durationPicker.html")
    local html = ""
    for each in f:lines() do
        html = html .. each .. "\n"
    end
    browser:html(html):bringToFront():show()
end

return obj
