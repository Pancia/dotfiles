# VPC File Format Specification

VPC (Virtual Private Context) files are JSON definitions in `vpc/` that describe workspace layouts — which apps to open, what URLs/commands to run, and how to position windows.

## Top-Level Structure

```json
{
    "space": "current",
    "yabai": { ... },
    "AppName": { ... }
}
```

### `space`

Which desktop space to switch to before launching.

| Value | Behavior |
|-------|----------|
| `"current"` | Stay on current space |
| `"1"` - `"9"` | Switch to that space number |

### `yabai`

Window tiling configuration. Uses CSS Grid-style named areas.

```json
"yabai": {
    "enabled": true,
    "layout": {
        "template": [
            "board browser browser iterm iterm",
            "board browser browser iterm iterm",
            "board browser browser iterm iterm"
        ]
    },
    "space_config": {
        "layout": "bsp",
        "balance": true
    }
}
```

- **template**: Grid rows. Each row is space-separated area names. Apps reference areas via `"area": "name"`.
- **space_config.layout**: Yabai layout mode (`bsp`, `float`, etc.)
- **space_config.balance**: Balance window sizes after placement.

Grid is converted to yabai format `rows:cols:start_x:start_y:width:height` automatically.

**Note:** Yabai cannot manage iTerm2 windows (empty AX roles). When iTerm has an `area` or `grid` config, `vpc.py` tells `iterm.py` to maximize via the iterm2 Python API instead.

## App Configurations

Keys that aren't `space`, `yabai`, or prefixed with `_` are treated as app configs. Prefixing with `_` disables an app (e.g. `"_qutebrowser"`).

### Common Properties

These apply to any app:

| Property | Type | Description |
|----------|------|-------------|
| `area` | string | Yabai grid area name (from template) |
| `grid` | string | Manual yabai grid spec, e.g. `"1:1:0:0:1:1"` |
| `resize` | array | Resize ops: `[{"anchor": "right", "x": 100, "y": 0}]` |
| `offset` | object | Relative move: `{"x": 50, "y": 100}` |
| `layer` | string | Window layer (`"normal"`, `"below"`, `"above"`) |
| `focus` | bool | Focus window after positioning |
| `position_delay` | float | Seconds to wait before positioning |
| `debug` | bool | Print debug info during positioning |

### Browsers (Google Chrome, Brave Browser, qutebrowser)

```json
"Google Chrome": {
    "area": "browser",
    "urls": [
        "http://localhost:9630/build/main",
        "http://localhost:3000/"
    ]
}
```

### iTerm2

Single instance:

```json
"iTerm2": {
    "area": "iterm",
    "dir": "$HOME/projects/myapp/",
    "tabs": [
        "@ start",
        ["@ docs", "claude"],
        [{"cmd": "@ log_live", "size": 30}, "@ status_live"]
    ]
}
```

Multiple instances (different areas):

```json
"iTerm2": [
    {
        "area": "iterm",
        "dir": "$HOME/projects/myapp/",
        "tabs": ["@ server", "@ vim", "git status"]
    },
    {
        "area": "board",
        "dir": "$HOME/ProtonDrive/wiki/personal",
        "tabs": ["vim pages/work%2Fproject.md"]
    }
]
```

### Kitty

Same tab format as iTerm2:

```json
"kitty": {
    "area": "main",
    "dir": "$HOME/dotfiles/sanctuary",
    "tabs": [
        ["fish main.fish", "fish timer.fish"]
    ]
}
```

### Generic Apps

Any app name opens via `open -a`:

```json
"Tuple": {}
```

### CotEditor

```json
"CotEditor": {
    "area": "board",
    "file": "$HOME/ProtonDrive/wiki/notes.md"
}
```

## Tab Format

The `tabs` array defines terminal tabs. Each entry is either a single-pane tab or a multi-pane tab with splits.

### Single Pane

A string creates a tab with one pane:

```json
"tabs": ["git status", "nvim", "@ server"]
```

### Split Panes

An array creates a tab with split panes:

```json
"tabs": [
    ["@ start", "@ log_live", "@ status_live"]
]
```

Strings in the array default to **vertical splits** with equal sizing.

### Split Panes with Options

Use objects for orientation and size control:

```json
"tabs": [
    [
        {"cmd": "@ start", "size": 47},
        {"cmd": "@ log_live", "size": 21},
        "@ status_live"
    ]
]
```

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `cmd` | string | required | Command to run |
| `vertical` | bool | `true` | `true` = side-by-side, `false` = stacked |
| `size` | int | equal | Percentage of available space |

Panes without `size` get the remaining space. Each new pane splits from the previous one.

## The `@` Prefix

`@` is an alias for `cmds` — the per-directory command runner. A tab command like `"@ start"` runs `cmds start` in the tab's directory.

Commands are defined in `cmds.rb` files stored at `~/dotfiles/cmds/<project-path>/cmds.rb`. See the `/cmds` skill for details on authoring commands.

## Path Expansion

`$HOME` and `~` are expanded in `dir` and file paths.

## Examples

### Minimal

```json
{
    "space": "current",
    "iTerm2": {
        "dir": "$HOME/projects/myapp/",
        "tabs": ["fish"]
    }
}
```

### Full Project Workspace

```json
{
    "yabai": {
        "enabled": true,
        "layout": {
            "template": [
                "board browser browser iterm iterm",
                "board browser browser iterm iterm",
                "board browser browser iterm iterm"
            ]
        }
    },
    "Google Chrome": {
        "area": "browser",
        "urls": [
            "http://localhost:9630/build/main",
            "http://localhost:3000/"
        ]
    },
    "iTerm2": [
        {
            "area": "iterm",
            "dir": "$HOME/projects/work/myapp/",
            "tabs": [
                "@ browser",
                "@ server",
                "@ vim",
                "@ claude",
                "git status"
            ]
        },
        {
            "area": "board",
            "dir": "$HOME/ProtonDrive/wiki/personal",
            "tabs": ["vim pages/work%2Fmyapp.md"]
        }
    ]
}
```
