-- Hermes Webview Profiling Test
-- Run from Hammerspoon console: require("lib/hermesProfileTest").run()

local obj = {}

local width = 500
local height = 400

function obj.run()
    local results = {}

    -- Measure webview creation
    local t0 = hs.timer.absoluteTime()

    local frame = hs.screen.primaryScreen():fullFrame()
    local rect = hs.geometry.rect(
        frame.x + (frame.w / 2) - (width / 2),
        frame.y + (frame.h / 2) - (height / 2),
        width, height
    )

    local t1 = hs.timer.absoluteTime()
    results.geometry = (t1 - t0) / 1000000

    -- Create webview with user content for messaging
    local uc = hs.webview.usercontent.new("HermesProfile")
    local renderComplete = false

    uc:setCallback(function(response)
        if response.body.rendered then
            local t3 = hs.timer.absoluteTime()
            results.jsCallback = (t3 - t0) / 1000000
            renderComplete = true

            -- Show results
            local msg = string.format(
                "Webview Profile Results:\n" ..
                "  Geometry calc: %.1fms\n" ..
                "  Browser create: %.1fms\n" ..
                "  HTML set: %.1fms\n" ..
                "  Show: %.1fms\n" ..
                "  JS rendered: %.1fms\n" ..
                "  TOTAL: %.1fms",
                results.geometry,
                results.browserCreate,
                results.htmlSet,
                results.show,
                results.jsCallback,
                results.jsCallback
            )
            print(msg)
            hs.alert.show(string.format("Webview total: %.0fms", results.jsCallback), 3)
        end
    end)

    local browser = hs.webview.newBrowser(rect, {developerExtrasEnabled = false}, uc)
    local t2 = hs.timer.absoluteTime()
    results.browserCreate = (t2 - t0) / 1000000

    -- Minimal HTML that signals when rendered
    local html = [[
<!DOCTYPE html>
<html>
<head>
<style>
* { margin: 0; padding: 0; box-sizing: border-box; }
body {
    background: #1a1a2e;
    color: #eee;
    font-family: -apple-system, BlinkMacSystemFont, system-ui, sans-serif;
    padding: 20px;
}
h1 { color: #00d4ff; margin-bottom: 16px; font-size: 24px; }
.menu-item {
    padding: 8px 12px;
    margin: 4px 0;
    background: #16213e;
    border-radius: 6px;
    cursor: pointer;
    display: flex;
    align-items: center;
}
.menu-item:hover { background: #0f3460; }
.key {
    background: #00d4ff;
    color: #1a1a2e;
    padding: 2px 8px;
    border-radius: 4px;
    margin-right: 12px;
    font-weight: bold;
    font-size: 14px;
}
.label { flex: 1; }
.submenu { color: #888; font-size: 12px; }
</style>
</head>
<body>
<h1>Hermes</h1>
<div class="menu-item"><span class="key">a</span><span class="label">Applications</span><span class="submenu">></span></div>
<div class="menu-item"><span class="key">w</span><span class="label">Windows</span></div>
<div class="menu-item"><span class="key">s</span><span class="label">System</span><span class="submenu">></span></div>
<div class="menu-item"><span class="key">t</span><span class="label">Tools</span><span class="submenu">></span></div>
<div class="menu-item"><span class="key">c</span><span class="label">Claude</span></div>
<div class="menu-item"><span class="key">:</span><span class="label">Search...</span></div>
<script>
window.webkit.messageHandlers.HermesProfile.postMessage({rendered: true});
</script>
</body>
</html>
]]

    browser:html(html)
    local t3 = hs.timer.absoluteTime()
    results.htmlSet = (t3 - t0) / 1000000

    browser:windowStyle({"borderless", "nonactivating"})
    browser:level(hs.canvas.windowLevels.floating)
    browser:bringToFront(true)
    browser:show()

    local t4 = hs.timer.absoluteTime()
    results.show = (t4 - t0) / 1000000

    -- Store reference and cleanup after 3 seconds
    obj._browser = browser
    hs.timer.doAfter(3, function()
        if obj._browser then
            obj._browser:delete()
            obj._browser = nil
        end
    end)

    return results
end

-- Quick test function
function obj.quick()
    local t0 = hs.timer.absoluteTime()
    obj.run()
    local t1 = hs.timer.absoluteTime()
    print(string.format("Sync portion: %.1fms", (t1 - t0) / 1000000))
end

return obj
