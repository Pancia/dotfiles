-- Hermes commands - pure Lua configuration
-- Ported from ~/.config/hermes/commands.py

local HOME = os.getenv("HOME")
local VPC_DIR = HOME .. "/dotfiles/vpc"
local SNIPPETS_FILE = HOME .. "/ProtonDrive/_config/snippets.txt"

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

local function assignKeys(items)
    -- Assign unique single-char keys to items based on first available char
    local result = {}
    local used = {}
    for _, item in ipairs(items) do
        local key = nil
        for i = 1, #item do
            local char = item:sub(i, i):lower()
            if char:match("%w") and not used[char] then
                key = char
                used[char] = true
                break
            end
        end
        if key then
            result[key] = item
        end
    end
    return result
end

-- ============================================================================
-- DYNAMIC MENU GENERATORS
-- ============================================================================

local function buildVpcMenu()
    local menu = {_desc = "VPC Workspaces"}
    local handle = io.popen("ls " .. VPC_DIR .. "/*.vpc 2>/dev/null")
    if not handle then
        menu.x = {"No VPC files found", "echo 'No .vpc files in ~/dotfiles/vpc/'"}
        return menu
    end

    local vpcFiles = {}
    for file in handle:lines() do
        local name = file:match("([^/]+)%.vpc$")
        if name then
            table.insert(vpcFiles, {name = name, path = file})
        end
    end
    handle:close()

    if #vpcFiles == 0 then
        menu.x = {"No VPC files found", "echo 'No .vpc files in ~/dotfiles/vpc/'"}
        return menu
    end

    -- Assign keys based on first char of name
    local used = {}
    for _, vpc in ipairs(vpcFiles) do
        local key = nil
        for i = 1, #vpc.name do
            local char = vpc.name:sub(i, i):lower()
            if char:match("%w") and not used[char] then
                key = char
                used[char] = true
                break
            end
        end
        if key then
            menu[key] = {vpc.name, HOME .. "/dotfiles/bin/vpc.py '" .. vpc.path .. "'"}
        end
    end

    return menu
end

local function buildServicesMenu()
    local menu = {_desc = "+services"}
    local handle = io.popen("launchctl list 2>/dev/null | grep org.pancia")
    if not handle then
        menu.x = {"No services found", "echo 'No org.pancia services found'"}
        return menu
    end

    local services = {}
    for line in handle:lines() do
        local pid, status, name = line:match("^(%S+)%s+(%S+)%s+(org%.pancia%.(%S+))")
        if name then
            local svcName = name:match("org%.pancia%.(.+)")
            if svcName then
                local running = pid ~= "-"
                table.insert(services, {name = svcName, running = running})
            end
        end
    end
    handle:close()

    if #services == 0 then
        menu.x = {"No services found", "echo 'No org.pancia services found'"}
        return menu
    end

    -- Sort and assign keys
    table.sort(services, function(a, b) return a.name < b.name end)
    local used = {}
    for _, svc in ipairs(services) do
        local key = nil
        for i = 1, #svc.name do
            local char = svc.name:sub(i, i):lower()
            if char:match("%w") and not used[char] then
                key = char
                used[char] = true
                break
            end
        end
        if key then
            local indicator = svc.running and "●" or "○"
            menu[key] = {
                _desc = svc.name .. " " .. indicator,
                s = {"Start", "service start " .. svc.name},
                t = {"Stop", "service stop " .. svc.name},
                r = {"Restart", "service restart " .. svc.name},
                l = {"Log", "service log " .. svc.name},
                e = {"Edit", "service edit " .. svc.name},
            }
        end
    end

    menu.n = {"New Service", "service create"}
    return menu
end

local function buildSnippetsMenu()
    local menu = {_desc = "+snippets"}
    menu.e = {"Edit Snippets", "nvim '" .. SNIPPETS_FILE .. "'"}

    local file = io.open(SNIPPETS_FILE, "r")
    if not file then
        menu.x = {"No snippets found", "echo 'Snippets file not found'"}
        return menu
    end

    local snippets = {}
    local current = nil

    for line in file:lines() do
        -- Check if this is a new snippet header (contains ':')
        local title, content = line:match("^([^:]+):(.*)$")
        if title and #title > 0 then
            if current then
                table.insert(snippets, current)
            end
            -- Parse optional trigger: "My Snippet [;ms]"
            local cleanTitle, trigger = title:match("^(.+)%s*%[([^%]]+)%]%s*$")
            current = {
                title = cleanTitle or title:match("^%s*(.-)%s*$"),
                content = content:match("^%s*(.-)%s*$") or "",
                trigger = trigger
            }
        elseif current and #line > 0 then
            current.content = current.content .. "\n" .. line
        end
    end
    if current then
        table.insert(snippets, current)
    end
    file:close()

    if #snippets == 0 then
        menu.x = {"No snippets found", "echo 'No snippets in file'"}
        return menu
    end

    -- Assign keys
    local used = {e = true}
    for _, snippet in ipairs(snippets) do
        local key = nil
        for i = 1, #snippet.title do
            local char = snippet.title:sub(i, i):lower()
            if char:match("%w") and not used[char] then
                key = char
                used[char] = true
                break
            end
        end
        if not key then
            for i = 0, 9 do
                local numKey = tostring(i)
                if not used[numKey] then
                    key = numKey
                    used[numKey] = true
                    break
                end
            end
        end
        if key then
            local display = snippet.title
            if snippet.trigger then
                display = snippet.title .. " [" .. snippet.trigger .. "]"
            end
            -- Escape content for shell
            local escaped = snippet.content:gsub("'", "'\\''")
            menu[key] = {display, "echo '" .. escaped .. "' | pbcopy && echo 'Copied: " .. snippet.title .. "'"}
        end
    end

    return menu
end

-- ============================================================================
-- COMMANDS DEFINITION
-- ============================================================================

return {
    c = {"calendar", "agenda 24"},

    d = {
        _desc = "+dotfiles",
        e = {"Edit dotfiles", "cd ~/dotfiles && v"},
    },

    l = {"LOCK IT DOWN", "launch-lock-screen-dialog"},

    j = {"Emoji Picker", [[hs -c 'hs.eventtap.keyStroke({"cmd", "ctrl", "alt", "shift"}, "j")']]},

    f = {
        _desc = "+finder",
        ["_"] = {"View spirituality", "finder-here $HOME/ProtonDrive/_spirituality"},
        b = {"View MediaBoard", "finder-here $HOME/MediaBoard"},
        d = {"View Dotfiles", "finder-here $HOME/dotfiles"},
        h = {"View Home", "finder-here $HOME"},
        i = {"View inbox", "finder-here $HOME/ProtonDrive/_inbox/"},
        m = {"View Media", "finder-here $HOME/Media"},
        o = {"View ProtonDrive", "finder-here $HOME/ProtonDrive"},
        p = {"View Projects", "finder-here $HOME/projects"},
        s = {"View Screenshots", "finder-here $HOME/Screenshots"},
        t = {"View transcripts", "finder-here $HOME/transcripts"},
        w = {"View Downloads", "finder-here $HOME/Downloads"},
        y = {"View YTDL", "finder-here $HOME/Downloads/ytdl/"},
    },

    -- 'a' and 'w' are handled by Hermes directly (built-in modes)
    -- a = App Launcher (built-in)
    -- w = Window Switcher (built-in)

    q = {
        _desc = "+apps",
        b = {"Brave", "open -a 'Brave Browser'"},
        c = {"Claude", "open -a Claude"},
        d = {"Discord", "open -a Discord"},
        g = {"Signal", "open -a Signal"},
        k = {"kosmik", "open -a 'Kosmik'"},
        l = {"Telegram", "open -a 'Telegram'"},
        o = {"Opera", "open -na 'Opera'"},
        p = {"Proton Password", "open -a 'Proton Pass'"},
        s = {"Spotify", "open -a Spotify"},
        t = {"iTerm", "open -a 'iTerm'"},
        v = {"Brave Beta (TV_BOARD)", "open -a 'Brave Browser Beta'"},
        x = {"Opera GX", "open -a 'Opera GX'"},
        z = {"Zen Browser", "open -a 'Zen Browser'"},
        w = {
            _desc = "+new window",
            b = {"Brave", "open -na 'Brave Browser'"},
            o = {"Opera", "open -na 'Opera'"},
            t = {"iTerm", "open -na 'iTerm'"},
            x = {"Opera GX", "open -na 'Opera GX'"},
        },
    },

    h = {
        _desc = "+hammerspoon",
        r = {"Reload", [[hs -c 'hs.eventtap.keyStroke({"cmd", "ctrl"}, "r")']]},
        c = {"Console", "hs -c 'hs.openConsole()'"},
        e = {"Edit init.lua", "nvim ~/dotfiles/lib/lua/init.lua"},
        s = {"Edit Seeds", "nvim ~/dotfiles/lib/lua/seeds/"},
    },

    k = {
        _desc = "+karabiner",
        e = {"Edit Config", "nvim ~/dotfiles/rcs/karabiner.json"},
        v = {"Event Viewer", "open -a 'Karabiner-EventViewer'"},
        k = {"Karabiner Elements", "open -a 'Karabiner-Elements'"},
    },

    p = buildSnippetsMenu,  -- Lazy generator

    s = buildServicesMenu,  -- Lazy generator

    v = buildVpcMenu,       -- Lazy generator

    y = {
        _desc = "+ytdl",
        i = {"ytdl interactive", "ytdl"},
        y = {"ytdl clipboard", "ytdl clipboard"},
    },

    u = {
        _desc = "+audio tools",
        l = {"Live Transcribe", "q live-transcribe"},
    },

    m = {
        _desc = "+music",
        c = {"Play or Pause", "cmus-remote --pause"},
        e = {"Edit Track", "cmedit"},
        y = {"Redownload from Youtube", "cmytdl"},
        a = {"Open Track in Audacity", "cmaudacity"},
        s = {"Select Track by Playlist", "music select"},
        t = {"Select Track by Tags", "music select --filter-by-tags"},
        n = {"Next Track", "cmus-remote --next"},
        p = {"Prev Track", "cmus-remote --prev"},
        l = {"Seek 10 Forwards", "cmus-remote --seek +10"},
        h = {"Seek 10 Backwards", "cmus-remote --seek -10"},
        ["."] = {"Seek 30 Forwards", "cmus-remote --seek +30"},
        [","] = {"Seek 30 Backwards", "cmus-remote --seek -30"},
        j = {"Volume Down", "cmus-remote --volume -5"},
        k = {"Volume Up", "cmus-remote --volume +5"},
    },

    t = {"open my yt playlists (WIP tv-board)", "open -na 'Brave Browser Beta' --args $(cat ~/Cloud/_config/my-youtube.playlists)"},

    ["="] = {"edit Hermes config", "nvim ~/dotfiles/lib/lua/seeds/hermes/commands.lua"},
    ["-"] = {"#!fish:~/private/bin/superwhisper_status", "~/private/bin/superwhisper_reset"},
}
