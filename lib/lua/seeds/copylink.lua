-- Copylink: put text on the clipboard from a clicked link.
--   hammerspoon://copy?text=<url-encoded text>
-- Lets a Claude Code reply (or any page) offer a "click to copy" link.
-- No alert on success: the clipboard seed already shows each new copy.

local obj = {}
obj._name = "copylink"

local config = {
    alertSeconds = 1.5,  -- only for the "no text" error alert
}

function obj:start(cfg)
    for k, v in pairs(cfg or {}) do config[k] = v end
    -- Hammerspoon URL-decodes query parameters before calling the handler.
    hs.urlevent.bind("copy", function(_, params)
        local text = params and params.text
        if not text or text == "" then
            hs.alert.show("copylink: no text in link", config.alertSeconds)
            return
        end
        hs.pasteboard.setContents(text)
    end)
    return self
end

function obj:stop()
    hs.urlevent.bind("copy", nil)
end

return obj
