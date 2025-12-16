# Hammerspoon Configuration

Hammerspoon is a powerful macOS automation tool that bridges macOS APIs with Lua scripting. This configuration uses a modular "seed" architecture for organizing functionality.

## Seed Architecture

Seeds are modular Lua modules located in `lib/lua/seeds/` that implement specific functionality.

### Core Concepts

- **Entry Point**: `~/.hammerspoon/init.lua` loads `lib/lua/init.lua`
- **Core Config**: `lib/lua/core.lua` - Main configuration and seed initialization
- **Seeds Directory**: `lib/lua/seeds/` - All seed modules
- **Libraries**: `lib/lua/lib/` - Shared utilities and helpers

### Seed Interface

Each seed module follows a standard interface:

```lua
local obj = {}

function obj:start(config)
  -- Initialize the seed with configuration
  return self
end

function obj:stop()
  -- Clean up resources
  return self
end

return obj
```

### Engage Function

Seeds are loaded using the `engage()` wrapper function that provides error handling:

```lua
function engage(seed_path, config)
  local success, result = pcall(function()
    local seed = require(seed_path)
    seed:start(config)
    return seed
  end)

  if not success then
    -- Show error notification and log
    return nil
  end

  return result
end
```

This ensures that if one seed fails to load, it doesn't crash the entire Hammerspoon configuration.

## Seeds Reference

| Seed | Purpose | Key Features |
|------|---------|--------------|
| **Curfew** | 9pm wind-down reminder | - Full-screen overlay at 9pm<br>- Hold-to-dismiss mechanic (not click)<br>- Escalating hold durations (5s→60s)<br>- Wake/start detection |
| **Hermes** | Application & workspace launcher | - App launcher with fuzzy matching<br>- VPC workspace launcher<br>- Multi-provider system (apps, slash commands, bang commands)<br>- Window switcher |
| **Snippets** | Text expansion system | - File-based snippet definitions<br>- Trigger-based auto-expansion<br>- Manual snippet chooser<br>- Clipboard integration |
| **Calendar** | Calendar event monitoring | - Tag-based event triggers<br>- Title-based event triggers<br>- Configurable lead time notifications<br>- Menubar countdown display |
| **Lotus** | Meditation & awareness timer | - Interval timer mode<br>- Clock-based trigger mode<br>- Dual-mode operation<br>- Sound notifications |
| **Cmus** | Music player control | - cmus integration<br>- Spotify integration<br>- Visual control panel<br>- Menubar status display |
| **Monitor** | Activity tracking | - Focus tracking (active window)<br>- Visible windows logging<br>- Activity detection (keyboard/mouse)<br>- JSON log format |
| **Watch** | Periodic script executor | - Configurable script intervals<br>- Delayed start support<br>- Log file management<br>- Menubar script status |
| **HomeBoard** | Visual dashboard | - Video player integration<br>- Dashboard display<br>- (Details in `lib/lua/seeds/homeboard/`) |

## Global Hotkeys

### System Control

| Hotkey | Action |
|--------|--------|
| `Cmd+Ctrl+C` | Toggle Hammerspoon console |
| `Cmd+Ctrl+R` | Reload Hammerspoon configuration |

### Application Launchers

| Hotkey | Action |
|--------|--------|
| `Cmd+Space` | App launcher (Hermes) with fuzzy search |
| `Alt+Tab` | Window switcher (fzf picker, all spaces) |

### Window Switcher

The window switcher (`Alt+Tab`) uses a global `windowFilter` in Hammerspoon to track windows across all spaces. It:

1. Queries `_G.windowFilter` for all windows (kept active via `keepActive()`)
2. Pipes window list to fzf for fuzzy selection
3. Focuses the selected window (works across spaces)

**Implementation**: `bin/window-switcher` script + `_G.windowFilter` in `lib/lua/core.lua`

### Navigation (Active Modal)

| Hotkey | Action |
|--------|--------|
| `Ctrl+J` | Navigate down in active chooser |
| `Ctrl+K` | Navigate up in active chooser |

### Media Controls - cmus

| Hotkey | Action |
|--------|--------|
| `F7` | Previous track |
| `F8` | Play/Pause |
| `F9` | Next track |
| `F13` | Volume down |
| `F14` | Volume up |

### Media Controls - Spotify

| Hotkey | Action |
|--------|--------|
| `Cmd+F7` | Previous track |
| `Cmd+F8` | Play/Pause |
| `Cmd+F9` | Next track |
| `Cmd+F13` | Volume down |
| `Cmd+F14` | Volume up |

### Snippets

| Hotkey | Action |
|--------|--------|
| `Cmd+Ctrl+S` | Open snippets chooser |

### Clipboard

| Hotkey | Action |
|--------|--------|
| `Cmd+Ctrl+P` | Open clipboard tool |

## Hermes: App Launcher & Provider System

Hermes implements a multi-provider architecture for different launcher modes.

### Provider System

Providers are triggered by query prefixes:

| Prefix | Provider | Purpose |
|--------|----------|---------|
| (none) | ApplicationProvider | Launch/focus applications |
| `/` | SlashProvider | Execute slash commands (e.g., `/vpc`) |
| `!` | BangProvider | Bang commands (not yet implemented) |

### Application Provider

- Scans running apps and `/Applications` directory
- Fuzzy matching with intelligent scoring:
  - Word boundary matches get bonus points
  - Consecutive character matches get bonus points
  - Earlier matches score higher
- Displays app icons (32x32)
- Launches or focuses apps on selection

### VPC Provider (Slash Commands)

Access via `/` prefix in launcher (e.g., `/vpc simplymeet`)

- Scans `~/dotfiles/vpc/*.vpc` files
- Parses JSON metadata for display
- Opens `.vpc` files with system default handler
- Fuzzy search across workspace names

## VPC Workspace System

VPC files are JSON definitions for workspace environments.

### File Location

`~/dotfiles/vpc/*.vpc`

### VPC File Format

```json
{
    "space": "current",
    "chrome": ["localhost:9630"],
    "brave": ["https://example.com"],
    "iterm": {
        "dir": "$HOME/projects/work/simplymeet/",
        "tabs": [
            "echo docker compose up",
            "echo shadow-cljs server",
            "echo clojure -J-Ddev -A:dev:local/nREPL",
            "echo vim",
            "echo gfa && gs"
        ]
    },
    "kitty": {
        "dir": "$HOME/projects/",
        "tabs": ["htop", "tail -f /var/log/system.log"]
    },
    "apps": ["Slack", "Discord"],
    "board": "dashboard-config"
}
```

### Supported Fields

- `space`: Desktop space number or "current"
- `chrome`: Array of URLs to open in Chrome
- `brave`: Array of URLs to open in Brave
- `iterm`: iTerm2 configuration with directory and tabs
- `kitty`: Kitty terminal configuration
- `apps`: Array of application names to launch
- `board`: HomeBoard dashboard configuration

## Snippets Seed

Text expansion system with file-based snippet storage.

### Configuration

```lua
local snippets = engage("seeds.snippets", {})
```

### Snippets File Format

Location: `~/ProtonDrive/_config/snippets.txt`

```
Snippet Title [trigger]: Snippet content here
Another Snippet: Multi-line content
  can span multiple lines
  preserving formatting

Email Signature [;sig]: Best regards,\nYour Name\nyou@example.com
```

### Features

- **Triggers**: Optional `[trigger]` in square brackets for auto-expansion
- **Manual Selection**: `Cmd+Ctrl+S` to browse and select snippets
- **Escape Sequences**: `\n` for newline, `\t` for tab
- **Clipboard Integration**: Selected snippets copied to clipboard
- **Auto-Expansion**: Type trigger anywhere to expand automatically

### Text Expansion

- Monitors keyboard input for trigger patterns
- Buffer limited to max trigger length for efficiency
- Resets buffer on modifiers, return, escape, tab, space
- Deletes trigger and pastes content via clipboard

## Calendar Seed

Monitors macOS Calendar events and triggers actions based on tags or titles.

### Configuration

```lua
local calendar = engage("seeds.calendar.init", {
    tagPattern = "#%{anthony/autocal:([%w-_]+)%}",
    pollInterval = 60,  -- seconds
    queryWindow = 3,    -- hours ahead
    triggers = {
        tags = {
            ["focus"] = {
                leadMinutes = 5,
                action = function(event)
                    hs.notify.new(function(notification)
                        hs.alert.show("Focus time in 5 minutes!")
                    end, {
                        title = "Focus Time Starting Soon",
                        informativeText = event.title
                    }):send()
                end
            }
        },
        titles = {
            ["Productivity & Accountability"] = {
                leadMinutes = 15,
                action = function(event)
                    -- Custom notification action
                end
            }
        }
    }
})
```

### Features

- **Tag Triggers**: Extract tags from event titles/notes using regex pattern
- **Title Triggers**: Match event titles with substring search
- **Lead Time**: Configure notification time before event starts
- **Deduplication**: Tracks triggered events to prevent duplicates
- **Menubar Display**: Shows countdown to next triggered event
- **Python Integration**: Uses Python script for calendar access

## Lotus: Meditation Timer

Dual-mode timer with interval and clock-based triggers.

### Configuration

```lua
local lotus = engage("seeds.lotus.init", {
    -- Interval mode (commented out in current config)
    -- interval = { minutes = 20 },

    -- Clock mode
    clockTriggers = {
        [0] = 1,   -- Top of hour plays sound 1
        [30] = 2,  -- Half hour plays sound 2
    },

    sounds = {
        {
            name  = "short",
            path  = "bowl.wav",
            notif = notif("Ohm... #short")
        },
        {
            name   = "long",
            path   = "gong.wav",
            volume = .5,
            notif  = notif("Ohm! #long")
        }
    }
})
```

### Modes

**Interval Mode**:
- Fixed duration countdown timer
- Cycles through configured sounds
- Menubar shows time remaining and current sound

**Clock Mode**:
- Triggers at specific minutes each hour
- Multiple triggers per hour supported
- Menubar shows next trigger time and sound

### Features

- Dual-mode operation (can run both simultaneously)
- Sleep/wake detection with state preservation
- Sound notifications with configurable volume
- Persistent state across Hammerspoon reloads
- Menubar controls for adding time and restarting

## Curfew: 9pm Wind-Down Reminder

Encourages stopping computer use after 9pm with a hold-to-dismiss overlay.

### Configuration

```lua
local curfew = engage("seeds.curfew", {
    triggerHour = 21,    -- 9pm
    resetHour = 4,       -- 4am
    holdDuration = 15    -- seconds to hold
})
```

### How It Works

1. **Checks every minute** if current time is in curfew window (9pm-4am)
2. **Full-screen overlay** appears with progress ring
3. **Hold mouse button** for 15 seconds to dismiss (not click)
4. **Returns in ~1 minute** (next timer tick)
5. **Repeats until 4am**

Simple polling approach - no complex state management or persistence needed.

## Cmus: Music Control

Integration with cmus music player and Spotify.

### Features

- **Dual Control**: cmus and Spotify support
- **Visual Panel**: Clickable menubar control panel with buttons
- **Status Display**: Current track in menubar with play/pause indicator
- **IPC Integration**: Real-time status updates via Hammerspoon IPC
- **Sleep Integration**: Auto-pause on system sleep

### Control Panel Buttons

- Row 1: Previous, Play/Pause, Next
- Row 2: Seek -30s, -10s, +10s, +30s
- Row 3: Volume down, Volume up
- Row 4: Select by Playlist, Select by Tags
- Row 5: Edit Track, Open in Audacity

### External Scripts

- `cmedit`: Edit track metadata
- `cmaudacity`: Open current track in Audacity
- `cmytdl`: YouTube download integration
- `cmselect`: Track selection by playlist
- `cmus-status-display`: IPC status reporter

## Monitor Seed

Tracks active window, visible windows, and user activity.

### Configuration

```lua
local monitor = engage("seeds.monitor", {})
```

### Features

- **Focus Tracking**: Logs currently focused window
- **Visible Windows**: Tracks all visible windows
- **Activity Detection**: Monitors keyboard and mouse activity
- **JSON Logging**: Daily log files with structured data

### Log Format

Location: `~/private/logs/monitor/YYYY_MM_DD.log.json`

```json
{"timestamp":"2025_12_14__10:30:00","focused":"Chrome => Documentation","visible":["iTerm2 => fish","Slack => #general"],"active":true}
,
{"timestamp":"2025_12_14__10:31:00","focused":"Chrome => Documentation","visible":["iTerm2 => fish","Slack => #general"],"active":false,"noChange":true}
```

### Fields

- `timestamp`: ISO-like timestamp format
- `focused`: "AppName => WindowTitle"
- `visible`: Array of visible window descriptions
- `active`: Boolean indicating keyboard/mouse activity in last interval
- `noChange`: Flag when focus/visible unchanged from previous entry

## Watch Seed

Executes shell scripts on configurable intervals.

### Configuration

```lua
local watch = engage("seeds.watch.init", {
    logDir = HOME .. "/.log/watch/",
    scripts = {
        {
            name = "disable_osx_startup_chime",
            command = HOME.."/dotfiles/misc/watch/disable_osx_startup_chime.watch.sh",
            triggerEvery = 60,  -- Multiplied by interval (60s)
            delayStart = 0
        },
        {
            name = "ytdl",
            command = HOME.."/dotfiles/misc/watch/ytdl/ytdl.watch.sh",
            triggerEvery = 15,
            delayStart = 5
        }
    }
})
```

### Features

- **Configurable Intervals**: `triggerEvery` multiplied by base interval (60s)
- **Delayed Start**: Optional delay before first execution
- **Log Files**: Per-script log files in `logDir`
- **Menubar Access**: View logs and execute scripts manually
- **Timer Display**: Shows seconds until next execution

## Spoons (Official Extensions)

Hammerspoon Spoons are official extensions installed via SpoonInstall.

### Installed Spoons

| Spoon | Purpose | Hotkey |
|-------|---------|--------|
| **ClipboardTool** | Clipboard history manager | `Cmd+Ctrl+P` |
| **FadeLogo** | Animated Hammerspoon logo on start | (automatic) |
| **SpoonInstall** | Spoon package manager | (internal) |

### Configuration

```lua
local install = hs.loadSpoon("SpoonInstall")
install.use_syncinstall = true

install:andUse("ClipboardTool", {
    start = true,
    hotkeys = {
        toggle_clipboard = {{"cmd", "ctrl"}, "p"}
    },
    config = {
        display_max_length = 50
    }
})

install:andUse("FadeLogo", {
    start = true,
    config = {default_run = 1.0}
})
```

## File Locations

### Primary Files

| Path | Purpose |
|------|---------|
| `~/.hammerspoon/init.lua` | Entry point (loads dotfiles config) |
| `~/dotfiles/lib/lua/init.lua` | Main initialization file |
| `~/dotfiles/lib/lua/core.lua` | Core configuration and seed loading |

### Seeds

| Path | Purpose |
|------|---------|
| `~/dotfiles/lib/lua/seeds/curfew.lua` | 9pm wind-down reminder |
| `~/dotfiles/lib/lua/seeds/hermes.lua` | App launcher & VPC system |
| `~/dotfiles/lib/lua/seeds/snippets.lua` | Text expansion |
| `~/dotfiles/lib/lua/seeds/calendar/init.lua` | Calendar monitoring |
| `~/dotfiles/lib/lua/seeds/lotus/init.lua` | Meditation timer |
| `~/dotfiles/lib/lua/seeds/cmus.lua` | Music control |
| `~/dotfiles/lib/lua/seeds/monitor.lua` | Activity tracking |
| `~/dotfiles/lib/lua/seeds/watch/init.lua` | Script executor |
| `~/dotfiles/lib/lua/seeds/homeboard/init.lua` | Dashboard system |

### Libraries

| Path | Purpose |
|------|---------|
| `~/dotfiles/lib/lua/lib/` | Shared utilities and helpers |
| `~/dotfiles/lib/lua/lib/dbg.lua` | Debug utilities |
| `~/dotfiles/lib/lua/lib/wakeDialog.lua` | Sleep/wake event handling |
| `~/dotfiles/lib/lua/lib/durationpicker.lua` | Duration picker UI |

### Data Files

| Path | Purpose |
|------|---------|
| `~/dotfiles/vpc/*.vpc` | VPC workspace definitions |
| `~/ProtonDrive/_config/snippets.txt` | Snippet definitions |
| `~/private/logs/monitor/` | Activity monitoring logs |
| `~/.log/watch/` | Watch script logs |

## Advanced Topics

### Error Handling

All seeds are loaded via `engage()` which uses `pcall()` to catch errors. Failed seeds:
- Display notification with error details
- Log error to console
- Don't crash the entire configuration
- Return `nil` so other seeds continue loading

### State Persistence

Seeds use `hs.settings` for persistent state:

```lua
-- Save state
hs.settings.set("key", value)

-- Load state
local saved = hs.settings.get("key")
```

Examples:
- Lotus saves timer state and position
- Calendar saves triggered event history
- Monitor tracks previous log entry for change detection

### Reload Protocol

When reloading Hammerspoon (`Cmd+Ctrl+R`):

1. Creates reload flag at `/tmp/hs_reloading`
2. Calls `stop()` on all registered seeds
3. Executes `hs.reload()`
4. Seeds detect reload flag and can adjust behavior

### IPC Communication

Hammerspoon IPC allows external scripts to communicate with running instance:

```bash
# From shell
hs -c 'hs.alert.show("Hello from shell")'

# Send message to named port
hs -c 'hs.ipc.localPort("cmus"):sendMessage("Track Name")'
```

Used by cmus seed for real-time status updates.

### Sleep/Wake Handling

Seeds using `lib/wakeDialog` can register callbacks:

```lua
local wake = require("lib/wakeDialog")

wake:onSleep(function()
    -- Handle sleep
end):onWake(function()
    -- Handle wake
end):start()
```

## Tips and Tricks

### Debugging

- `Cmd+Ctrl+C`: Open console to see logs and errors
- Use `hs.printf()` or `print()` for debug logging
- Check `~/Library/Logs/Hammerspoon/console.log` for crash logs

### Customization

1. Edit `lib/lua/core.lua` to enable/disable seeds
2. Modify seed configurations when calling `engage()`
3. Create new seeds following the standard interface
4. Add VPC workspaces as `.vpc` JSON files

### Performance

- Hermes caches application list for fast fuzzy search
- Monitor uses 60-second polling to minimize overhead
- Calendar polls every 60 seconds (configurable)
- Text expansion buffer limited to max trigger length

### Extending

To create a new seed:

1. Create `lib/lua/seeds/myseed.lua`
2. Implement `start(config)` and `stop()` methods
3. Load in `core.lua`: `local myseed = engage("seeds.myseed", {})`
4. Optionally register in global `seeds` table for reload support
