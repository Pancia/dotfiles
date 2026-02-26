# Dotfiles

Personal development environment for macOS. Focused on automation, productivity, and multi-tool integration.

## Repository Structure

```
dotfiles/
├── fish/           # Fish shell configuration (primary shell)
├── nvim/           # Neovim configuration (Lua + Vimscript)
├── lib/lua/        # Hammerspoon configuration (macOS automation)
├── rcs/            # Config files managed via rcs/MANIFEST symlinks
├── bin/            # CLI utilities (50+ scripts)
├── services/       # Background LaunchAgent services
├── vpc/            # VPC workspace definitions
├── zsh/            # Zsh configuration (legacy, deprecated)
├── lib/            # Language-specific libraries (ruby, python, etc.)
├── misc/           # Miscellaneous tools and data
├── wiki/           # Personal wiki/knowledge base
├── ai/             # AI prompts and templates
├── install         # Installation script
└── Brewfile        # Homebrew packages
```

## Key Patterns

### RC Metadata System
Files in `rcs/` are managed via `rcs/MANIFEST` using `source -> destination` format:
```
tmux.conf -> $HOME/.tmux.conf
ghostty.config -> $HOME/.config/ghostty/config
```
The `_ENSURE_RCS()` function in `fish/config.fish` parses the MANIFEST and creates symlinks from `~/dotfiles/rcs/file` to the destination. It runs automatically in the background on every Fish shell startup (`_ENSURE_RCS &`). Some `rcs/` files have vestigial `#<[...]>` inline headers that are no longer parsed. Directories are always symlinked; files are also symlinked (not hardlinked).

### Seed Architecture (Hammerspoon)
Hammerspoon modules in `lib/lua/seeds/` follow a standard interface:
- `start(config)` - Initialize the seed
- `stop()` - Clean up resources
- `engage()` wrapper provides error handling via pcall
- **Never call `hs.reload()` programmatically** - ask the user to reload with `Cmd+Ctrl+R`

### Auto-Loading (Fish)
- `conf.d/*.fish` - Sourced on shell startup
- `functions/*.fish` - Lazy-loaded on first call
- Fisher plugins auto-installed on missing

### Fish Shell Gotchas
Common pitfalls when writing Fish functions:

| Gotcha | Wrong | Right |
|--------|-------|-------|
| **Escape sequences** | `"text\twith\ttabs"` (literal `\t`) | `printf '%s\t%s' "$a" "$b"` |
| **Variable scoping** | `set -l var` inside if/for block | Declare at function level, assign inside block |
| **List vs string** | `"$list"` joins with spaces | `$list` keeps elements separate |
| **Multi-line output** | `printf '%s\n' "$list"` (one line) | `printf '%s\n' $list` (many lines) |
| **Piping to functions** | `cmd | my_func` with `cat`/`string collect` | Write to temp file, pass as argument |

**Variable scoping example:**
```fish
# WRONG - $msg not visible outside if block
if test $big
    set -l msg (generate_message)
end
echo $msg  # empty!

# RIGHT - declare first, assign inside
set -l msg
if test $big
    set msg (generate_message)
end
echo $msg  # works
```

## Quick Reference

### Installation
```bash
cd ~/dotfiles
./install all    # Run all setup tasks
./install brew   # Just Homebrew packages
./install nvim   # Just Neovim setup
```

### Key Hotkeys (Hammerspoon)
| Hotkey | Action |
|--------|--------|
| `Cmd+Space` | App launcher (Hermes) |
| `Cmd+Ctrl+R` | Reload Hammerspoon |
| `Cmd+Ctrl+C` | Hammerspoon console |
| `Cmd+Ctrl+S` | Snippets chooser |
| `Cmd+Ctrl+P` | Clipboard tool |
| `Alt+Tab` | Window switcher (fzf, all spaces) |
| `F7/F8/F9` | Media controls (cmus) |

### Shell Commands (Fish)
| Command | Action |
|---------|--------|
| `Ctrl+S` | fzfm leader menu (fuzzy finder) |
| `d` | Directory bookmarks |
| `q` | Command registry |
| `z` | Jump to directory |
| `astro` | Astrological transit tracker |
| `service` | LaunchAgent manager (list/start/stop/restart/log/status) |

### Neovim Prefixes
| Prefix | Commands |
|--------|----------|
| `;p` | Plugin management |
| `;s` | LSP commands |
| `;f` | Fuzzy finder (FZF) |
| `;;` | Show all commands |

### Testing
**Always use `cmds test` to run tests** - never run pytest directly with python. The `cmds` script handles virtual environments and dependencies.

```bash
cmds test yt            # Run youtube-transcribe tests
cmds test yt -v         # Verbose output
cmds test yt --cov      # With coverage report
cmds test yt -k "cache" # Run tests matching pattern
```

## Primary Tools

| Tool | Purpose | Config Location |
|------|---------|-----------------|
| **Fish** | Primary shell | `fish/` |
| **Neovim** | Editor | `nvim/` |
| **Hammerspoon** | macOS automation | `lib/lua/` |
| **Karabiner** | Keyboard customization | `rcs/karabiner.json` |
| **Yabai** | Window tiling | (via VPC workspaces) |
| **Astro** | Astrological transits | `bin/astro`, `~/.local/share/astro/` |

### Hours Calculation
`lib/python/hours.py` - Parse time entries and calculate hours worked with optional multipliers.

```python
from lib.python.hours import calc_hours
calc_hours([
    "1/29 : 01:00 - 01:50 (ai-mult 2.00) - description",
    "2/3  : 19:40 - 01:00 - no multiplier, defaults to 1x",
])
```

Format: `DATE : HH:MM - HH:MM (ai-mult N.NN) - description`
- Handles overnight spans (e.g. 23:55 - 01:55)
- `(ai-mult ...)` and description are optional

### VPC Workspaces

Virtual Private Context (VPC) workspaces are pre-configured desktop environments launched via Hammerspoon Hermes.

**Launching:** `Cmd+Space` -> `v` -> pick workspace (e.g. `a` for altera, `f` for festivar)

**Testing from CLI:** `python3 ~/dotfiles/bin/vpc.py ~/dotfiles/vpc/<name>.vpc`

**Creating a new VPC:** Copy `vpc/template.vpc` and edit, or inspect an existing one like `vpc/festivar.vpc`.

**Key files:**
- `vpc/*.vpc` - Workspace definitions (JSON)
- `bin/vpc.py` - Main orchestrator
- `bin/iterm.py` - iTerm2 tab/split launcher (uses iterm2 Python API)
- `bin/kitty.py` - Kitty tab/split launcher

**Yabai note:** Yabai cannot manage iTerm2 windows (empty AX roles). When a VPC has a yabai layout for iTerm, `vpc.py` passes `--maximize` to `iterm.py` which uses the iterm2 API to set the window frame directly.

See [docs/vpc-schema.md](docs/vpc-schema.md) for the full VPC file format specification.

## Detailed Documentation

| Document | Contents |
|----------|----------|
| [docs/fish.md](docs/fish.md) | Fish shell conf.d, functions, fzfm, plugins |
| [docs/neovim.md](docs/neovim.md) | Neovim plugins, LSP, keymaps, settings |
| [docs/hammerspoon.md](docs/hammerspoon.md) | Seeds, hotkeys, VPC system, Spoons |
| [docs/services.md](docs/services.md) | LaunchAgents, VPC workspaces, bin utilities |
| [docs/vpc-schema.md](docs/vpc-schema.md) | VPC file format specification |
| [docs/astro.md](docs/astro.md) | Astrological transit tracker CLI |

## File Locations

### Entry Points
- Fish: `fish/config.fish` -> `~/.config/fish/config.fish`
- Neovim: `nvim/init.vim` -> `~/.config/nvim/init.vim`
- Hammerspoon: `~/.hammerspoon/init.lua` -> loads `lib/lua/init.lua`

### Important Directories
- Functions: `fish/functions/` (169 files)
- Seeds: `lib/lua/seeds/` (9 modules)
- Utilities: `bin/` (50+ scripts)
- Services: `services/` (6 LaunchAgents)
- Workspaces: `vpc/` (10 VPC definitions)
