local json = require("hs.json")
local safeLogger = require("lib/safeLogger")
local menubarRegistry = require("lib/menubarRegistry")

local obj = {}

obj.spoonPath = os.getenv("HOME").."/dotfiles/lib/lua/seeds/calendar/"

-- Default configuration
obj.tagPattern = "#([%w-_]+)"  -- Lua pattern for hashtag extraction
obj.pollInterval = 60           -- seconds
obj.queryWindow = 24            -- hours ahead
obj.triggers = {                -- trigger configuration
    tags = {},                  -- tag -> {leadMinutes, action}
    titles = {}                 -- title substring -> {leadMinutes, action}
}
obj.pythonPath = os.getenv("HOME").."/.pyenv/shims/python3"

function obj:start(config)
    obj._logger = safeLogger.new("Calendar", "debug")
    obj._logger.df("Starting calendar seed...")

    -- Merge config
    for k,v in pairs(config) do obj[k] = v end

    -- Backward compatibility: migrate old trigger format to new nested structure
    if obj.triggers and not obj.triggers.tags and not obj.triggers.titles then
        obj._logger.df("Migrating old trigger format to new structure")
        local oldTriggers = obj.triggers
        obj.triggers = {
            tags = oldTriggers,
            titles = {}
        }
    end

    -- Ensure triggers structure exists
    obj.triggers = obj.triggers or {}
    obj.triggers.tags = obj.triggers.tags or {}
    obj.triggers.titles = obj.triggers.titles or {}

    -- Initialize state
    obj._triggeredEvents = hs.settings.get("calendar_triggered_events") or {}
    obj._cachedEvents = nil  -- Will be populated by async query

    -- Count triggered events
    local triggeredCount = 0
    for _ in pairs(obj._triggeredEvents) do
        triggeredCount = triggeredCount + 1
    end
    obj._logger.df("Loaded %d triggered events from state", triggeredCount)

    -- Get or create persistent menubar (survives soft reloads)
    local mb, isNew = menubarRegistry.getOrCreate("calendar")
    obj._menubar = mb

    -- Always update menu callback (points to new code after reload)
    obj._menubar:setMenu(function() return obj:renderMenu() end)

    -- Only set initial title if newly created
    if isNew then
        obj._menubar:setTitle("📅")
    end

    -- Start polling timer
    obj._pollTimer = hs.timer.doEvery(obj.pollInterval, function()
        obj:heartbeat()
    end)

    -- Defer initial poll and menubar render to avoid blocking startup
    obj._initTimer = hs.timer.doAfter(0, function()
        local start = hs.timer.absoluteTime()
        obj:heartbeat()
        obj:renderMenuBar()
        hs.printf("[deferred] calendar.init: %.1fms", (hs.timer.absoluteTime() - start) / 1e6)
    end)

    return self
end

-- Soft stop: cleanup resources but preserve menubar (for soft reload)
function obj:softStop()
    obj._logger.df("Soft stopping calendar seed...")

    -- Save state
    hs.settings.set("calendar_triggered_events", obj._triggeredEvents)

    -- Stop any pending query task
    if obj._queryTask then
        obj._queryTask:terminate()
        obj._queryTask = nil
    end

    -- Stop timers
    if obj._initTimer then
        obj._initTimer:stop()
    end
    if obj._pollTimer then
        obj._pollTimer:stop()
    end

    -- NOTE: Do NOT delete menubar - it persists across soft reloads
    obj._menubar = nil

    return self
end

-- Hard stop: full cleanup including menubar (for hard reload)
function obj:stop()
    obj._logger.df("Stopping calendar seed...")
    obj:softStop()
    menubarRegistry.delete("calendar")
    return self
end

function obj:getNextTriggeredEvent()
    -- Find the next upcoming event with a configured tag or title trigger
    local events = obj:queryEvents()
    if not events then
        return nil
    end

    local nextEvent = nil
    local nextTime = nil
    local nextTriggerInfo = nil  -- {tags = {list}, titleMatches = {list}}

    for _, event in ipairs(events) do
        local hasConfiguredTrigger = false
        local triggerInfo = {tags = {}, titleMatches = {}}

        -- Check tag triggers
        local tags = obj:extractEventTags(event)
        for _, tag in ipairs(tags) do
            if obj.triggers.tags[tag] then
                hasConfiguredTrigger = true
                table.insert(triggerInfo.tags, tag)
            end
        end

        -- Check title triggers
        local titleMatches = obj:getMatchingTitleTriggers(event)
        for _, match in ipairs(titleMatches) do
            hasConfiguredTrigger = true
            table.insert(triggerInfo.titleMatches, match.searchString)
        end

        if hasConfiguredTrigger then
            local secondsUntil = obj:getSecondsUntilEvent(event)
            if secondsUntil and secondsUntil > 0 then
                if not nextTime or secondsUntil < nextTime then
                    nextEvent = event
                    nextTime = secondsUntil
                    nextTriggerInfo = triggerInfo
                end
            end
        end
    end

    return nextEvent, nextTime, nextTriggerInfo
end

function obj:formatTimeUntil(seconds)
    -- Format seconds into human-readable string
    if seconds < 60 then
        return string.format("%ds", seconds)
    elseif seconds < 3600 then
        return string.format("%dm", math.floor(seconds / 60))
    else
        local hours = math.floor(seconds / 3600)
        local mins = math.floor((seconds % 3600) / 60)
        if mins == 0 then
            return string.format("%dh", hours)
        else
            return string.format("%dh%dm", hours, mins)
        end
    end
end

function obj:renderMenuBar()
    local nextEvent, timeUntil, triggerInfo = obj:getNextTriggeredEvent()

    if nextEvent and timeUntil and triggerInfo then
        local displayParts = {}

        -- Add tags
        for _, tag in ipairs(triggerInfo.tags) do
            table.insert(displayParts, "#" .. tag)
        end

        -- Add title matches (show first match only in menubar to save space)
        if #triggerInfo.titleMatches > 0 then
            table.insert(displayParts, "[" .. triggerInfo.titleMatches[1] .. "]")
        end

        local triggerStr = table.concat(displayParts, " ")
        local timeStr = obj:formatTimeUntil(timeUntil)
        obj._menubar:setTitle(string.format("📅 %s %s", timeStr, triggerStr))
    else
        obj._menubar:setTitle("📅")
    end
end

function obj:renderMenu()
    local menu = {
        {title = "Force poll now", fn = function()
            obj:heartbeat()
            hs.notify.new({title = "Calendar", informativeText = "Polled events"}):send()
        end},
        {title = "-"},
    }

    -- Show upcoming triggered events
    local events = obj:queryEvents()
    if events then
        local triggeredEvents = {}

        for _, event in ipairs(events) do
            local hasConfiguredTrigger = false
            local displayParts = {}

            -- Check tag triggers
            local tags = obj:extractEventTags(event)
            for _, tag in ipairs(tags) do
                if obj.triggers.tags[tag] then
                    hasConfiguredTrigger = true
                    table.insert(displayParts, "#" .. tag)
                end
            end

            -- Check title triggers
            local titleMatches = obj:getMatchingTitleTriggers(event)
            for _, match in ipairs(titleMatches) do
                hasConfiguredTrigger = true
                table.insert(displayParts, "[" .. match.searchString .. "]")
            end

            if hasConfiguredTrigger then
                local secondsUntil = obj:getSecondsUntilEvent(event)
                if secondsUntil and secondsUntil > 0 then
                    table.insert(triggeredEvents, {
                        event = event,
                        displayParts = displayParts,
                        secondsUntil = secondsUntil
                    })
                end
            end
        end

        -- Sort by time
        table.sort(triggeredEvents, function(a, b)
            return a.secondsUntil < b.secondsUntil
        end)

        -- Add to menu (max 5)
        local count = math.min(#triggeredEvents, 5)
        if count > 0 then
            table.insert(menu, {title = "Upcoming triggered events:", disabled = true})

            for i = 1, count do
                local item = triggeredEvents[i]
                local timeStr = obj:formatTimeUntil(item.secondsUntil)
                local triggerStr = table.concat(item.displayParts, " ")
                local title = string.format("  %s - %s %s", timeStr, item.event.title, triggerStr)

                table.insert(menu, {title = title, disabled = true})
            end

            table.insert(menu, {title = "-"})
        end
    end

    -- Add utility options
    table.insert(menu, {title = "Clear trigger history", fn = function()
        obj._triggeredEvents = {}
        hs.settings.set("calendar_triggered_events", {})
        hs.notify.new({title = "Calendar", informativeText = "Cleared trigger history"}):send()
    end})

    local triggerCount = 0
    for _ in pairs(obj._triggeredEvents) do
        triggerCount = triggerCount + 1
    end

    table.insert(menu, {title = string.format("Tracked triggers: %d", triggerCount), disabled = true})

    return menu
end

function obj:extractTags(text)
    -- Extract tags from text using configured pattern
    if not text or text == "" then
        return {}
    end

    local tags = {}
    local seen = {}  -- Track unique tags

    for tag in text:gmatch(obj.tagPattern) do
        if not seen[tag] then
            table.insert(tags, tag)
            seen[tag] = true
        end
    end

    return tags
end

function obj:extractEventTags(event)
    -- Extract all tags from event title and notes
    local titleTags = obj:extractTags(event.title)
    local notesTags = obj:extractTags(event.notes)

    -- Combine and deduplicate
    local allTags = {}
    local seen = {}

    for _, tag in ipairs(titleTags) do
        if not seen[tag] then
            table.insert(allTags, tag)
            seen[tag] = true
        end
    end

    for _, tag in ipairs(notesTags) do
        if not seen[tag] then
            table.insert(allTags, tag)
            seen[tag] = true
        end
    end

    return allTags
end

function obj:matchesTitleSubstring(eventTitle, searchString)
    -- Check if event title contains the search string (case-insensitive)
    if not eventTitle or eventTitle == "" then
        return false
    end
    if not searchString or searchString == "" then
        return false
    end

    -- Trim whitespace and convert to lowercase for case-insensitive comparison
    local titleLower = eventTitle:gsub("^%s*(.-)%s*$", "%1"):lower()
    local searchLower = searchString:gsub("^%s*(.-)%s*$", "%1"):lower()

    local found = titleLower:find(searchLower, 1, true) ~= nil

    return found
end

function obj:getMatchingTitleTriggers(event)
    -- Get all configured title substrings that match this event
    local matches = {}

    for searchString, triggerConfig in pairs(obj.triggers.titles) do
        if obj:matchesTitleSubstring(event.title, searchString) then
            table.insert(matches, {
                searchString = searchString,
                config = triggerConfig
            })
        end
    end

    return matches
end

function obj:queryEvents()
    -- Return cached events (updated asynchronously by queryEventsAsync)
    return obj._cachedEvents
end

function obj:queryEventsAsync(callback)
    -- Call Python script asynchronously to get calendar events
    local scriptPath = obj.spoonPath .. "calendar_query.py"

    obj._logger.vf("Querying events (async)")

    -- Cancel any pending query task
    if obj._queryTask then
        obj._queryTask:terminate()
        obj._queryTask = nil
    end

    obj._queryTask = hs.task.new(obj.pythonPath, function(exitCode, stdout, stderr)
        obj._queryTask = nil

        if exitCode ~= 0 then
            obj._logger.ef("Calendar query failed (exit %d): %s", exitCode, stderr)
            if callback then callback(nil) end
            return
        end

        -- Parse JSON
        local success, data = pcall(json.decode, stdout)
        if not success then
            obj._logger.ef("Failed to parse JSON: %s", data)
            if callback then callback(nil) end
            return
        end

        if not data.success then
            obj._logger.ef("Calendar query failed: %s", data.error or "unknown error")
            if callback then callback(nil) end
            return
        end

        obj._logger.vf("Found %d events", data.count)

        -- Update cache
        obj._cachedEvents = data.events

        if callback then callback(data.events) end
    end, {scriptPath, tostring(obj.queryWindow)})

    obj._queryTask:start()
end

function obj:parseEventDate(dateStr)
    -- Parse date format: "2025-01-04 15:30:00" (local timezone)
    local year, month, day, hour, min, sec = dateStr:match("(%d+)-(%d+)-(%d+) (%d+):(%d+):(%d+)")

    if not year then
        obj._logger.ef("Failed to parse date: %s", dateStr)
        return nil
    end

    -- Convert to epoch timestamp (local time)
    return os.time({
        year = tonumber(year),
        month = tonumber(month),
        day = tonumber(day),
        hour = tonumber(hour),
        min = tonumber(min),
        sec = tonumber(sec)
    })
end

function obj:getSecondsUntilEvent(event)
    -- Calculate seconds until event starts
    local startTime = obj:parseEventDate(event.start)
    if not startTime then
        return nil
    end

    local now = os.time()
    return startTime - now
end

function obj:getTriggerKey(eventId, identifier, triggerKind, triggerType)
    -- Create unique key for tracking triggered events
    -- identifier: tag name or title pattern
    -- triggerKind: "tag" or "title"
    -- triggerType: "before-start", etc.
    return string.format("%s-%s:%s-%s", eventId, triggerKind, identifier, triggerType)
end

function obj:hasTriggered(eventId, identifier, triggerKind, triggerType)
    -- Check if this event+identifier+kind+type has already triggered
    local key = obj:getTriggerKey(eventId, identifier, triggerKind, triggerType)
    return obj._triggeredEvents[key] ~= nil
end

function obj:markTriggered(eventId, identifier, triggerKind, triggerType)
    -- Mark event+identifier+kind+type as triggered with timestamp
    local key = obj:getTriggerKey(eventId, identifier, triggerKind, triggerType)
    obj._triggeredEvents[key] = os.time()
    obj._logger.df("Marked as triggered: %s", key)

    -- Persist immediately to prevent loss on crash/reload
    hs.settings.set("calendar_triggered_events", obj._triggeredEvents)
end

function obj:cleanupOldTriggers()
    -- Remove trigger records older than 48 hours
    local cutoff = os.time() - (48 * 3600)
    local removed = 0

    for key, timestamp in pairs(obj._triggeredEvents) do
        if timestamp < cutoff then
            obj._triggeredEvents[key] = nil
            removed = removed + 1
        end
    end

    if removed > 0 then
        obj._logger.df("Cleaned up %d old trigger records", removed)
        -- Persist after cleanup
        hs.settings.set("calendar_triggered_events", obj._triggeredEvents)
    end
end

function obj:shouldTrigger(event, identifier, triggerKind, triggerConfig)
    -- Check if this event should trigger now
    -- identifier: tag name or title pattern
    -- triggerKind: "tag" or "title"
    local secondsUntil = obj:getSecondsUntilEvent(event)
    if not secondsUntil then
        obj._logger.df("  [%s:%s] No secondsUntil for event '%s'", triggerKind, identifier, event.title)
        return false
    end

    obj._logger.df("  [%s:%s] Event '%s' starts in %ds", triggerKind, identifier, event.title, secondsUntil)

    -- Don't trigger past events
    if secondsUntil < 0 then
        obj._logger.df("  [%s:%s] Event '%s' is in the past", triggerKind, identifier, event.title)
        return false
    end

    -- Check if already triggered
    if obj:hasTriggered(event.id, identifier, triggerKind, "before-start") then
        obj._logger.df("  [%s:%s] Event '%s' already triggered", triggerKind, identifier, event.title)
        return false
    end

    -- Calculate trigger window
    local leadSeconds = triggerConfig.leadMinutes * 60
    local windowMin = leadSeconds - obj.pollInterval
    local windowMax = leadSeconds + obj.pollInterval

    obj._logger.df("  [%s:%s] Trigger window: %ds to %ds (lead: %ds, poll: %ds)",
        triggerKind, identifier, windowMin, windowMax, leadSeconds, obj.pollInterval)

    -- Check if within trigger window
    if secondsUntil >= windowMin and secondsUntil <= windowMax then
        obj._logger.df("  [%s:%s] ✓ Event '%s' is within trigger window!", triggerKind, identifier, event.title)
        return true
    else
        obj._logger.df("  [%s:%s] ✗ Event '%s' outside window (secondsUntil=%d, need %d-%d)",
            triggerKind, identifier, event.title, secondsUntil, windowMin, windowMax)
    end

    return false
end

function obj:processEvents(events)
    -- Process events and trigger actions
    if not events then
        obj._logger.df("No events to process")
        return
    end

    obj._logger.vf("Processing %d events...", #events)
    local triggeredCount = 0

    for _, event in ipairs(events) do
        -- Check tag-based triggers
        local tags = obj:extractEventTags(event)

        if #tags > 0 then
            obj._logger.df("Event '%s' has tags: %s", event.title, table.concat(tags, ", "))
        end

        for _, tag in ipairs(tags) do
            local triggerConfig = obj.triggers.tags[tag]

            if triggerConfig then
                obj._logger.df("Checking trigger for tag '%s' (lead: %dm)", tag, triggerConfig.leadMinutes)
                if obj:shouldTrigger(event, tag, "tag", triggerConfig) then
                    obj._logger.df("Triggering action for tag '%s' on event '%s'", tag, event.title)

                    -- Mark as triggered first
                    obj:markTriggered(event.id, tag, "tag", "before-start")

                    -- Execute action
                    local success, err = pcall(function()
                        triggerConfig.action(event)
                    end)

                    if not success then
                        obj._logger.ef("Error executing action for tag '%s': %s", tag, err)
                    else
                        triggeredCount = triggeredCount + 1
                    end
                end
            else
                obj._logger.df("Tag '%s' has no configured trigger", tag)
            end
        end

        -- Check title-based triggers
        local titleMatches = obj:getMatchingTitleTriggers(event)

        if #titleMatches > 0 then
            obj._logger.df("Event '%s' matches %d title triggers", event.title, #titleMatches)
        end

        for _, match in ipairs(titleMatches) do
            local searchString = match.searchString
            local triggerConfig = match.config

            obj._logger.df("Checking trigger for title '%s' (lead: %dm)", searchString, triggerConfig.leadMinutes)
            if obj:shouldTrigger(event, searchString, "title", triggerConfig) then
                obj._logger.df("Triggering action for title '%s' on event '%s'", searchString, event.title)

                -- Mark as triggered first
                obj:markTriggered(event.id, searchString, "title", "before-start")

                -- Execute action
                local success, err = pcall(function()
                    triggerConfig.action(event)
                end)

                if not success then
                    obj._logger.ef("Error executing action for title '%s': %s", searchString, err)
                else
                    triggeredCount = triggeredCount + 1
                end
            end
        end
    end

    if triggeredCount > 0 then
        obj._logger.df("Triggered %d actions this cycle", triggeredCount)
    else
        obj._logger.vf("No actions triggered this cycle")
    end
end

function obj:heartbeat()
    obj._logger.vf("Calendar heartbeat - polling events...")

    -- Query events asynchronously
    obj:queryEventsAsync(function(events)
        -- Process events and trigger actions
        obj:processEvents(events)

        -- Cleanup old triggers periodically (every ~100 polls = ~100 minutes)
        if math.random(100) == 1 then
            obj:cleanupOldTriggers()
        end

        -- Update menubar
        obj:renderMenuBar()
    end)
end

return obj
