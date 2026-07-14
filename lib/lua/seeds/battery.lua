-- Battery: low-battery alerts for Bluetooth peripherals (keyboard / mouse).
-- Polls bin/bt-battery on a timer and fires tiered, deduped hs.notify alerts.

local safeLogger = require("lib/safeLogger")

local obj = {}
obj._name = "battery"
obj._logger = safeLogger.new("battery", "info")

-- Configuration (overridable via start())
local config = {
    tiers        = { 20, 10, 5 },  -- alert as % crosses each tier downward
    pollInterval = 600,            -- seconds (10 min); battery drains slowly
    rearmAbove   = 25,             -- climb above this to re-arm (a real recharge)
    devices      = { keyboard = true, mouse = true },  -- lowercased minorTypes
    alertUnknown = false,          -- also alert devices we couldn't classify
}

-- State
obj._timer = nil
obj._state = {}          -- address -> { tier = <lowest tier already alerted, or nil> }
obj._notifications = {}  -- address -> live hs.notify ref (withdraw before replacing)

-- Lowest configured tier at/below `pct`, or nil if above all tiers.
local function tierFor(pct)
    local hit = nil
    for _, t in ipairs(config.tiers) do
        if pct <= t and (hit == nil or t < hit) then hit = t end
    end
    return hit
end

function obj:alert(d, pct, tier)
    if obj._notifications[d.address] then
        obj._notifications[d.address]:withdraw()
    end
    local critical = tier <= 10
    local n = hs.notify.new(nil, {
        title           = critical and "🪫 Critical battery" or "🔋 Low battery",
        informativeText = string.format("%s (%s) at %d%%", d.type, d.name, pct),
        withdrawAfter   = 0,  -- persist; battery warnings shouldn't silently vanish
        soundName       = critical and "Basso" or "default",
    })
    obj._notifications[d.address] = n
    n:send()
    obj._logger.i(string.format("alert %s %d%% (tier %d)", d.type, pct, tier))
end

function obj:evaluate(d)
    local pct = tonumber(d.percent)  -- defensive: never trust the type
    if pct == nil or not d.address then return end

    local watched = config.devices[(d.type or ""):lower()]
        or (config.alertUnknown and (d.type == nil or d.type == "Unknown"))
    if not watched then
        obj._logger.i(string.format("skip %s (%s) %s%%",
            tostring(d.type), tostring(d.name), pct))
        return
    end

    local st = obj._state[d.address] or {}
    if pct > config.rearmAbove then
        st.tier = nil  -- recharged: re-arm for the next drain cycle
    else
        local tier = tierFor(pct)
        -- Alert only when crossing to a LOWER tier than last alerted.
        if tier and (st.tier == nil or tier < st.tier) then
            obj:alert(d, pct, tier)
            st.tier = tier
        end
    end
    obj._state[d.address] = st
end

function obj:poll()
    local helper = os.getenv("HOME") .. "/dotfiles/bin/bt-battery"
    hs.task.new(helper, function(code, stdout, _stderr)
        if code ~= 0 then
            obj._logger.w("bt-battery exit " .. tostring(code))
            return
        end
        local ok, devices = pcall(hs.json.decode, stdout)
        if not ok or type(devices) ~= "table" then return end
        for _, d in ipairs(devices) do
            -- One malformed entry must not abort the whole poll.
            local ok2, err = pcall(function() obj:evaluate(d) end)
            if not ok2 then obj._logger.w("evaluate error: " .. tostring(err)) end
        end
    end, { "--json" }):start()
end

function obj:start(cfg)
    obj._logger.i("Starting battery monitor")
    if cfg then
        for k, v in pairs(cfg) do config[k] = v end
    end
    obj:poll()  -- check immediately on load
    obj._timer = hs.timer.doEvery(config.pollInterval, function() obj:poll() end)
    return obj
end

function obj:stop()
    obj._logger.i("Stopping battery monitor")
    if obj._timer then
        obj._timer:stop()
        obj._timer = nil
    end
    for _, n in pairs(obj._notifications) do n:withdraw() end
    obj._notifications = {}
    obj._state = {}
end

return obj
