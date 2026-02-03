-- Performance monitoring utility for Hammerspoon
-- Logs slow operations to help diagnose keyboard lag

local obj = {}

-- Configuration
obj.threshold_ms = 16  -- Log anything slower than 16ms (one frame at 60fps)
obj.eventtap_threshold_ms = 5  -- Eventtaps should be very fast
obj.log_all = false  -- Set to true to log all operations, not just slow ones
obj.enabled = true

-- Circular buffer for recent slow operations
obj._history = {}
obj._history_max = 100
obj._history_idx = 0

-- Stats tracking
obj._stats = {}

-- ANSI colors for console output
local RED = "\27[31m"
local YELLOW = "\27[33m"
local GREEN = "\27[32m"
local CYAN = "\27[36m"
local RESET = "\27[0m"

-- Format milliseconds with color based on severity
local function formatMs(ms, threshold)
    local color = GREEN
    if ms > threshold * 2 then
        color = RED
    elseif ms > threshold then
        color = YELLOW
    end
    return string.format("%s%.2fms%s", color, ms, RESET)
end

-- Track an operation with timing
-- Usage: local elapsed = perfmon.track("monitor.writeLog", function() ... end)
function obj.track(name, fn)
    if not obj.enabled then
        return fn()
    end

    local start = hs.timer.absoluteTime()
    local results = {fn()}
    local elapsed_ns = hs.timer.absoluteTime() - start
    local elapsed_ms = elapsed_ns / 1e6

    -- Update stats
    if not obj._stats[name] then
        obj._stats[name] = {
            count = 0,
            total_ms = 0,
            max_ms = 0,
            slow_count = 0
        }
    end
    local stat = obj._stats[name]
    stat.count = stat.count + 1
    stat.total_ms = stat.total_ms + elapsed_ms
    if elapsed_ms > stat.max_ms then
        stat.max_ms = elapsed_ms
    end

    local threshold = name:match("eventtap") and obj.eventtap_threshold_ms or obj.threshold_ms

    if elapsed_ms > threshold then
        stat.slow_count = stat.slow_count + 1

        -- Add to history
        obj._history_idx = (obj._history_idx % obj._history_max) + 1
        obj._history[obj._history_idx] = {
            time = os.date("%H:%M:%S"),
            name = name,
            elapsed_ms = elapsed_ms
        }

        -- Log slow operation
        hs.printf("[%sPERFMON SLOW%s] %s: %s (threshold: %dms)",
            RED, RESET, name, formatMs(elapsed_ms, threshold), threshold)
    elseif obj.log_all then
        hs.printf("[PERFMON] %s: %s", name, formatMs(elapsed_ms, threshold))
    end

    return table.unpack(results)
end

-- Wrap a function to automatically track its performance
-- Usage: local wrappedFn = perfmon.wrap("myOperation", originalFn)
function obj.wrap(name, fn)
    return function(...)
        local args = {...}
        return obj.track(name, function()
            return fn(table.unpack(args))
        end)
    end
end

-- Create a scoped timer for manual start/stop timing
-- Usage: local timer = perfmon.start("operation"); ... ; timer.stop()
function obj.start(name)
    local startTime = hs.timer.absoluteTime()
    return {
        stop = function()
            local elapsed_ms = (hs.timer.absoluteTime() - startTime) / 1e6
            local threshold = name:match("eventtap") and obj.eventtap_threshold_ms or obj.threshold_ms

            if elapsed_ms > threshold then
                hs.printf("[%sPERFMON SLOW%s] %s: %s", RED, RESET, name, formatMs(elapsed_ms, threshold))
            elseif obj.log_all then
                hs.printf("[PERFMON] %s: %s", name, formatMs(elapsed_ms, threshold))
            end

            return elapsed_ms
        end
    }
end

-- Get recent slow operations
function obj.getHistory()
    local result = {}
    for i = 1, #obj._history do
        local idx = ((obj._history_idx - i) % obj._history_max) + 1
        if obj._history[idx] then
            table.insert(result, obj._history[idx])
        end
    end
    return result
end

-- Get stats summary
function obj.getStats()
    local result = {}
    for name, stat in pairs(obj._stats) do
        table.insert(result, {
            name = name,
            count = stat.count,
            avg_ms = stat.total_ms / stat.count,
            max_ms = stat.max_ms,
            slow_count = stat.slow_count,
            slow_pct = (stat.slow_count / stat.count) * 100
        })
    end
    table.sort(result, function(a, b) return a.slow_count > b.slow_count end)
    return result
end

-- Print stats summary to console
function obj.printStats()
    local stats = obj.getStats()
    print("\n" .. CYAN .. "=== PERFMON STATS ===" .. RESET)
    print(string.format("%-40s %8s %10s %10s %10s", "Operation", "Count", "Avg(ms)", "Max(ms)", "Slow%"))
    print(string.rep("-", 80))
    for _, stat in ipairs(stats) do
        local color = stat.slow_pct > 10 and RED or (stat.slow_pct > 1 and YELLOW or "")
        print(string.format("%s%-40s %8d %10.2f %10.2f %9.1f%%%s",
            color, stat.name:sub(1, 40), stat.count, stat.avg_ms, stat.max_ms, stat.slow_pct, RESET))
    end
end

-- Print recent slow operations
function obj.printHistory()
    local history = obj.getHistory()
    print("\n" .. CYAN .. "=== RECENT SLOW OPERATIONS ===" .. RESET)
    for i, entry in ipairs(history) do
        if i > 20 then break end
        print(string.format("[%s] %s: %.2fms", entry.time, entry.name, entry.elapsed_ms))
    end
end

-- Reset stats
function obj.reset()
    obj._stats = {}
    obj._history = {}
    obj._history_idx = 0
end

-- Export to global for console access
_G.perfmon = obj

return obj
