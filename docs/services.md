# Services, VPC Workspaces, and Utilities

Documentation for background services, Virtual Private Context (VPC) workspaces, and command-line utilities in the dotfiles system.

## Background Services (services/)

LaunchAgent plist files that run as background daemons on macOS. Each service is configured to start automatically and maintain persistent operation.

### Available Services

| Service | Purpose | Plist File |
|---------|---------|------------|
| **bookmark-manager** | Manages bookmark synchronization and organization | `org.pancia.bookmark-manager.plist` |
| **copyparty** | File sharing server for network file access | `org.pancia.copyparty.plist` |
| **sanctuary** | Sanctuary application background service | `org.pancia.sanctuary.plist` |
| **syncthing** | Continuous file synchronization across devices | `org.pancia.syncthing.plist` |
| **tv-board** | TV board display service | `org.pancia.tv-board.plist` |
| **vpc** | VPC workspace management daemon | `org.pancia.vpc.plist` |

### Service Configuration

Each service follows this structure:
- **Location**: `services/{service-name}/`
- **Plist file**: `org.pancia.{service-name}.plist`
- **Launch script**: `dotfiles-services-{service-name}.sh`
- **Logs**: `~/.log/services/{service-name}.log`

Standard plist properties:
- `RunAtLoad`: Auto-start on login
- `KeepAlive`: Automatic restart on crash
- `StandardOutPath` / `StandardErrorPath`: Log file locations

## VPC Workspace System (vpc/)

Virtual Private Context (VPC) workspaces provide pre-configured desktop environments with specific applications, window layouts, and automation.

### Available VPC Workspaces

| VPC File | Purpose |
|----------|---------|
| `test.vpc` | Testing workspace with board, browser, and terminal layout |
| `festivar.vpc` | Festivar project workspace |
| `gkeep-import.vpc` | Google Keep import workflow |
| `logseq-commit.vpc` | Logseq commit automation |
| `sanctuary.vpc` | Sanctuary app development environment |
| `obs.vpc` | OBS recording setup |
| `remote-sync.vpc` | Remote synchronization workspace |
| `simply-meet.vpc` | Meeting/conference setup |
| `ytdl-process.vpc` | YouTube download processing |
| `template.vpc` | Template for creating new VPCs |

### VPC File Format

VPC definitions are JSON files with the following structure:

```json
{
  "space": "current",
  "yabai": {
    "enabled": true,
    "layout": {
      "template": [
        "area1 area2 area3",
        "area1 area2 area3"
      ]
    }
  },
  "AppName": {
    "area": "area1",
    "urls": ["https://example.com"],
    "resize": [{"anchor": "right", "x": 100, "y": 0}]
  },
  "iTerm2": [...],
  "kitty": {...}
}
```

### VPC Components

#### Space Management
- **space**: Target desktop space (`"current"`, `"next"`, or specific number)
- **yabai**: Window tiling configuration with layout templates

#### Supported Applications

**Browsers**:
- Chrome
- Brave Browser
- qutebrowser
- Configuration includes URLs, window placement, and sizing

**Terminals**:
- **iTerm2**: Tab/split configuration with directory and command setup
- **Kitty**: Tab management with initial commands
- Both support area placement and multi-tab layouts

**Other Apps**:
- Board integration for note-taking
- Custom app launching via app-launcher

### Launching VPC Workspaces

VPC workspaces are launched via Hammerspoon Hermes system:
- Prefix: `/` followed by VPC name
- Example: `/test` launches `test.vpc`
- VPC daemon handles workspace orchestration

## Key bin/ Utilities (bin/)

Command-line utilities for system automation and workflow management. Total: 47 utilities.

### Core Utilities

| Script | Purpose |
|--------|---------|
| **app-launcher** | Application switching with fuzzy matching and multi-mode support |
| **hermes** | UI modal system for macOS with keyboard-driven controls |
| **hermes-centered** | Centered variant of hermes |
| **current-space** | Space/desktop management and querying |

### Terminal Management

| Script | Purpose |
|--------|---------|
| **iterm.py** | iTerm2 tab/split management and automation |
| **kitty.py** | Kitty terminal window and tab management |
| **open-iterm-with** | Quick iTerm2 launcher with presets |

### AI & Development

| Script | Purpose |
|--------|---------|
| **ai_chat.py** | AI chat interface for terminal interactions |
| **git-hotspots** | Git repository analysis and change frequency tracking |
| **claude_to_md.py** | Convert Claude conversation exports to Markdown |

### Command Registry

| Script | Purpose |
|--------|---------|
| **cmds** | Command registry interface and launcher |
| **cmedit** | Edit command registry entries |
| **cmselect** | Fuzzy select from command registry |
| **cmtag** | Tag-based command filtering |
| **cmpick** | Pick and execute registered commands |

### Specialized Command Launchers

| Script | Purpose |
|--------|---------|
| **cmaudacity** | Audacity-specific commands |
| **cmytdl** | YouTube download commands |

### Media & Content

| Script | Purpose |
|--------|---------|
| **music** | Music player control utilities |
| **cmus-status-display** | Display current cmus player status |
| **estimate_youtube_downloads.py** | Estimate download sizes and durations |

### Other Utilities

| Script | Purpose |
|--------|---------|
| **activate-whispering** | Speech recognition activation |
| **agrep** | Advanced grep wrapper |
| **filament-open-file** | Filament editor file opener |

## File Locations

```
dotfiles/
├── services/
│   ├── bookmark-manager/
│   │   └── org.pancia.bookmark-manager.plist
│   ├── copyparty/
│   │   └── org.pancia.copyparty.plist
│   ├── sanctuary/
│   │   └── org.pancia.sanctuary.plist
│   ├── syncthing/
│   │   └── org.pancia.syncthing.plist
│   ├── tv-board/
│   │   └── org.pancia.tv-board.plist
│   └── vpc/
│       └── org.pancia.vpc.plist
│
├── vpc/
│   ├── test.vpc
│   ├── festivar.vpc
│   ├── gkeep-import.vpc
│   ├── logseq-commit.vpc
│   ├── sanctuary.vpc
│   ├── obs.vpc
│   ├── remote-sync.vpc
│   ├── simply-meet.vpc
│   ├── template.vpc
│   └── ytdl-process.vpc
│
└── bin/
    ├── app-launcher
    ├── hermes
    ├── iterm.py
    ├── kitty.py
    ├── music
    ├── ai_chat.py
    ├── git-hotspots
    ├── cmds
    ├── cmedit
    └── ... (47 total utilities)
```

## Integration Points

### Hammerspoon Integration
- VPC workspaces launched via Hermes modal system
- App launcher triggered via keyboard shortcuts
- Controls modal system for UI overlays

### Window Management
- Yabai tiling configuration in VPC workspaces
- Dynamic area-based layout templates
- Automatic window placement and sizing

### Terminal Automation
- iTerm2 and Kitty script integration
- Multi-tab/split configurations
- Directory-specific workspace setup

### Service Management
- LaunchAgent auto-start on login
- Persistent background processes
- Centralized logging in `~/.log/services/`
