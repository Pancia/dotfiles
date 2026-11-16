-- Rolevote: record a + or − vote on a roleplay character or universe.
--
-- Short form, what the bookends use:
--   hammerspoon://r?v=<id><slot>
-- <id> is the 4-character vote id the roll hook (roleplay-roll) adds to each
-- roll and logs, with the character and universe, in rolls.tsv. <slot> is 1-8:
--   1 opener character +   2 opener character −
--   3 opener universe  +   4 opener universe  −
--   5-8 the same for the closer.
-- The spoken line is not stored here. Lines the roleplay-bookends mod wrote
-- are in ~/.local/state/roleplay/mod-lines.jsonl under their voteId and kind
-- (opener or closer); older lines the main model wrote: search the
-- transcripts for "r?v=<id>".
--
-- Long form, from before the id existed (it carries everything itself):
--   hammerspoon://rate?vote=up|down&kind=character|universe&name=<n>&line=<l>
--
-- Both append one line to votes.tsv:
--   time  id  place  vote  kind  name  rolled  line
-- place is opener or closer; rolled is the roll's own time from rolls.tsv,
-- which tells two rolls apart if an id ever repeats. Fields a form does not
-- have are left empty.

local obj = {}
-- Running rolevotes-review tasks, kept referenced until each one ends.
obj._tasks = {}
obj._name = "rolevote"

-- Hardcoded on purpose: Hammerspoon starts from launchd and has no
-- XDG_STATE_HOME, so reading it here would always fall back to this anyway.
-- If roleplay-roll logs elsewhere (XDG_STATE_HOME or ROLEPLAY_ROLL_LOG), pass
-- the paths in hammerspoon.lua: engage("seeds.rolevote", {rolls = ..., votes = ...}).
local dir = os.getenv("HOME") .. "/.local/state/roleplay"
local config = {
    votes = dir .. "/votes.tsv",
    rolls = dir .. "/rolls.tsv",
    alertSeconds = 1,
}

local SIGN = { up = "+", down = "−" }
local KINDS = { character = true, universe = true }
-- slot digit -> place, kind, vote
local SLOTS = {}
for i, place in ipairs({ "opener", "closer" }) do
    local base = (i - 1) * 4
    SLOTS[base + 1] = { place, "character", "up" }
    SLOTS[base + 2] = { place, "character", "down" }
    SLOTS[base + 3] = { place, "universe", "up" }
    SLOTS[base + 4] = { place, "universe", "down" }
end

-- One record per line: tabs and line breaks inside a field become spaces.
local function clean(s)
    return (tostring(s or ""):gsub("[\t\r\n]+", " "))
end

local function append(fields)
    local d = config.votes:match("^(.*)/[^/]+$")
    if d then os.execute("mkdir -p '" .. d:gsub("'", "'\\''") .. "'") end
    local f, err = io.open(config.votes, "a")
    if not f then
        hs.alert.show("rolevote: cannot write: " .. tostring(err), 3)
        return false
    end
    for i, v in ipairs(fields) do fields[i] = clean(v) end
    f:write(table.concat(fields, "\t"), "\n")
    f:close()
    return true
end

-- The character, universe and roll time an id belongs to, from the roll log.
-- The newest match wins, in case an id ever repeats.
local function lookup(id)
    local f = io.open(config.rolls, "r")
    if not f then return nil end
    local character, universe, rolled
    for line in f:lines() do
        local t, lid, c, u = line:match("^([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)$")
        if lid == id then character, universe, rolled = c, u, t end
    end
    f:close()
    return character, universe, rolled
end

function obj:start(cfg)
    for k, v in pairs(cfg or {}) do config[k] = v end

    hs.urlevent.bind("r", function(_, params)
        local id, digit = tostring((params or {}).v or ""):match("^([0-9a-z][0-9a-z][0-9a-z][0-9a-z])([1-8])$")
        local slot = SLOTS[tonumber(digit or "")]
        if not id or not slot then
            hs.alert.show("rolevote: bad link", config.alertSeconds)
            return
        end
        local place, kind, vote = slot[1], slot[2], slot[3]
        local character, universe, rolled = lookup(id)
        local name = (kind == "character") and character or universe
        -- An id the roll log lacks is still recorded, but the alert says so:
        -- such a vote cannot be traced to a character.
        if append({ os.date("%Y-%m-%d %H:%M:%S"), id, place, vote, kind, name or "", rolled or "", "" }) then
            if name then
                hs.alert.show(SIGN[vote] .. " " .. name, config.alertSeconds)
            else
                hs.alert.show(SIGN[vote] .. " unknown vote id " .. id, 3)
            end
        end
    end)

    hs.urlevent.bind("rate", function(_, params)
        params = params or {}
        local vote, kind, name = params.vote, params.kind, params.name
        if not SIGN[vote] or not KINDS[kind] or not name or name == "" then
            hs.alert.show("rolevote: bad link", config.alertSeconds)
            return
        end
        if append({ os.date("%Y-%m-%d %H:%M:%S"), "", "", vote, kind, name, "", params.line or "" }) then
            hs.alert.show(SIGN[vote] .. " " .. clean(name), config.alertSeconds)
        end
    end)
    -- hammerspoon://rolevotes: open a Claude session in a new iTerm tab to
    -- review the votes. The roleplay-bookends mod's reminder row no longer
    -- links here (its Review button runs bin/rolevotes-review itself).
    hs.urlevent.bind("rolevotes", function()
        local script = os.getenv("HOME") .. "/dotfiles/bin/rolevotes-review"
        local task
        task = hs.task.new(script, function(code, _, err)
            obj._tasks[task] = nil
            if code ~= 0 then
                -- "" is true in Lua: an empty stderr still needs a reason.
                local why = (err and err ~= "") and err or ("exit " .. code)
                hs.alert.show("rolevotes: " .. why, 3)
            end
        end)
        -- Held until its callback runs, or Hammerspoon may collect the task
        -- and the failure alert never shows.
        if task and task:start() then
            obj._tasks[task] = true
        else
            hs.alert.show("rolevotes: cannot start " .. script, 3)
        end
    end)
    return self
end

function obj:stop()
    hs.urlevent.bind("r", nil)
    hs.urlevent.bind("rate", nil)
    hs.urlevent.bind("rolevotes", nil)
end

return obj
