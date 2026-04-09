# Dotfiles

Personal development environment for macOS. Focused on automation, productivity, and multi-tool integration.

## VCS

This is a **jj (Jujutsu) repository**. Use `jj` for all VCS operations — do not use `git` directly. See the global CLAUDE.md for jj workflow details.

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
├── vendor/         # Vendored dependencies (MANIFEST.json tracked, clones gitignored)
├── cmd/vendor/     # Vendor CLI source (Go)
├── public/         # Static HTML pages and redirect utilities
├── install         # Installation script
└── Brewfile        # Homebrew packages
```

## LaunchAgent Services

Use the `service` CLI (not `launchctl` directly) for managing LaunchAgents:
```bash
service list              # List all services
service status            # Status of all services
service start <name>      # Start a service
service stop <name>       # Stop a service
service restart <name>    # Restart a service
service log <name>        # Show logs for a service
service create            # Create a new service
service edit <name>       # Edit a service's script and plist
```

### Available Services

| Service | Schedule | Purpose |
|---------|----------|---------|
| `ziplog` | Thursday 12:00 | Compress monitor logs >6 days old, archive by month, backup to `~/Cloud/_inbox/monitor/minimac/` |
| `disk-snapshot` | Daily 12:30 | Create disk usage snapshot to `~/.local/share/disk-snapshots/` |
| `bookmark-manager` | Daily 2:00 | Sync browser bookmarks |
| `sanctuary` | On demand | Rotate encrypted backup directories |
| `copyparty` | Startup | Media server for file sharing |

See `service list` for all installed services. `bin/ziplog` can also be run manually with `ziplog --yes` (skips confirmation prompt).

## Key Patterns

### RC Metadata System
Files in `rcs/` are managed via `rcs/MANIFEST` using `source -> destination` format:
```
tmux.conf -> $HOME/.tmux.conf
ghostty.config -> $HOME/.config/ghostty/config
```
The `_ENSURE_RCS()` function in `fish/config.fish` parses the MANIFEST and creates symlinks from `~/dotfiles/rcs/file` to the destination. It runs automatically in the background on every Fish shell startup (`_ENSURE_RCS &`). Some `rcs/` files have vestigial `#<[...]>` inline headers that are no longer parsed. Directories are symlinked; files are hard linked.

### Seed Architecture (Hammerspoon)
Hammerspoon modules in `lib/lua/seeds/` follow a standard interface:
- `start(config)` - Initialize the seed
- `stop()` - Clean up resources
- `engage()` wrapper provides error handling via pcall
- **Never call `hs.reload()` programmatically** - ask the user to reload with `Cmd+Ctrl+R`

### Monitor Seed (Activity Logger)
The `monitor` seed (`lib/lua/seeds/monitor.lua`) logs the focused window every 20 seconds to `~/.local/share/monitor/YYYY_MM_DD.log.json`. Each entry is a JSON object with `timestamp`, `focused` (app name + window title), and `active` (whether keyboard/mouse input occurred since last entry). Repeated same-window entries get a `noChange: true` flag. The file is append-only comma-separated JSON objects (not a JSON array).

### Auto-Loading (Fish)
- `conf.d/*.fish` - Sourced on shell startup
- `functions/*.fish` - Lazy-loaded on first call
- Fisher plugins auto-installed on missing

### Fish Shell Gotchas
**REQUIRED: Run `/fish` before writing or modifying ANY `.fish` file.** Fish syntax differs from bash/zsh in subtle ways that cause bugs. Do not skip this step.

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

### Session Review
After each interactive Claude Code session, a background Haiku process reviews the session transcript and suggests CLAUDE.md updates. Results are written to `.cc/pending-updates-<timestamp>-<session-id>.md`.

**How it works:**
1. `bin/cc-session-summary` — extracts review-optimized session summary (human messages, file paths, tool use) with 150k char budget
2. `fish/functions/cc-session-review.fish` — sends summary + current CLAUDE.md to Haiku, writes suggestions
3. Triggered automatically by `fish/functions/my-claude-code-wrapper.fish` after `claude` exits (non-interactive invocations skipped)

**Viewing suggestions:** Pending updates appear in `chpwd` output when you cd into a project with pending files (golden/orange highlight). Use `/cc:pending-updates` to automatically find, review, apply, and clean up pending update files in the current directory. Alternatively, manually review files and delete them after applying edits.

### Claude Code Project Artifacts

Files in `.cc/` are Claude Code session artifacts:
- `pending-updates-<ts>-<id>.md` — suggested CLAUDE.md edits from session reviews
- `PLAN-*.md` — session plans and design documents

Tracked in git via `!.cc` in `gitignore_global`.

## Quick Reference

### Installation
```bash
cd ~/dotfiles
./install all    # Run all setup tasks
./install brew   # Just Homebrew packages
./install nvim   # Just Neovim setup
```

### XDG Base Directories

The project uses XDG Base Directory Specification for tool configuration and caches. Environment variables are set in `fish/conf.d/00_xdg.fish` (loaded first, alphabetically):

| Variable | Value | Used By |
|----------|-------|---------|
| `XDG_CONFIG_HOME` | `~/.config` | git, tmux, docker, aws, etc. |
| `XDG_DATA_HOME` | `~/.local/share` | cargo, bundle, gem, hex, etc. |
| `XDG_STATE_HOME` | `~/.local/state` | history files, cache, logs |
| `XDG_CACHE_HOME` | `~/.cache` | npm, maven, gradle, gitlibs, deps.clj |

Relocated tool configs:
- **Git**: `~/.config/git/` (replaces `~/.gitconfig`)
- **Tmux**: `~/.config/tmux/` (replaces `~/.tmux.conf`)
- **Cargo**: `~/.local/share/cargo` (replaces `~/.cargo`)
- **Docker**: `~/.config/docker`
- **AWS**: `~/.config/aws`
- **Gradle**: `~/.local/share/gradle` (replaces `~/.gradle`)

Symlinked items (data in `~/.local/`, but still accessible at `~/.`):
- `.flet`, `.dartServer`, `.dart-tool`, `.flutter-devtools` → `~/.local/state/` and `~/.local/share/`
- `.log` → `~/.local/state/log`

### Key Hotkeys (Hammerspoon)
| Hotkey | Action |
|--------|--------|
| `Cmd+Space` | App launcher (Hermes, standalone Swift app) |
| `Cmd+Ctrl+R` | Reload Hammerspoon |
| `Cmd+Ctrl+C` | Hammerspoon console |
| `Cmd+Ctrl+S` | Snippets chooser |
| `Cmd+Ctrl+P` | Clipboard tool |
| `Alt+Tab` | Window switcher (fzf/yabai, all spaces) |
| `F7/F8/F9` | Media controls (cmus) |

### Shell Commands (Fish)
| Command | Action |
|---------|--------|
| `Ctrl+S` | fzfm leader menu (fuzzy finder) |
| `d` | Directory bookmarks |
| `q` | Command registry |
| `z` | Jump to directory |
| `astro` | Astrological transit tracker |
| `ccsave [title]` | Save current Claude Code session to `.cc/sessions.json` (autogenerates title if omitted) |
| `service` | LaunchAgent manager (list/start/stop/restart/log/status) |
| `tab-organize windows` | List open browser windows with tab counts |
| `tab-organize plan [--window ID]` | Generate AI organization plan (editable before execute) |
| `tab-organize execute <plan-file>` | Apply tab organization commands via browser extension |

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

### Claude Code Config (cc-config)

Project-level skill/agent/command configuration via `.cc-config` and `cc-config.json`:

- **`.cc-config`** (local, per-project) — lists groups/skills/agents/commands to enable (one per line)
- **`cc-config.json`** (global registry at `~/dotfiles/ai/`) — defines all available skills, agents, commands, and groups
- **`"default"` key** in cc-config.json — group to auto-sync into `.claude/` when a project lacks `.cc-config`

**Workflow:**
```bash
cc-config              # Show profile and sync status (no args defaults to show)
cc-config init        # Create .cc-config via fzf picker
cc-config edit        # Edit .cc-config with reference comments
cc-config show        # Show what's enabled for current project (+ sync status)
cc-config sync        # Sync based on .cc-config (no args required)
cc-config sync --force # Clear stamp and force re-sync (fixes stale symlinks)
cc-config list        # Show all registered skills/agents/commands
```

The wrapper auto-syncs on `claude` launch: if `.cc-config` exists, uses that; otherwise syncs the `"default"` group from `cc-config.json`. Running `cc-config sync` manually now updates the stamp, keeping it in sync with the wrapper's cache.

## Primary Tools

| Tool | Purpose | Config Location |
|------|---------|-----------------|
| **Fish** | Primary shell | `fish/` |
| **Neovim** | Editor | `nvim/` |
| **Hammerspoon** | macOS automation | `lib/lua/` |
| **Karabiner** | Keyboard customization | `rcs/karabiner.json` |
| **Yabai** | Window tiling | (via VPC workspaces) |
| **Astro** | Astrological transits | `bin/astro`, `~/.local/share/astro/` |
| **uv** | Python package manager & venv tool | `fish/conf.d/uv.fish` |

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

Virtual Private Context (VPC) workspaces are pre-configured desktop environments launched via Hermes (`Cmd+Space` → `v`).

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

### Website Crawler

`bin/crawl-sitemap` — recursively crawls a website and lists all internal pages. BFS traversal, skips static assets, deduplicates.

```bash
crawl-sitemap <url>              # list all pages
crawl-sitemap <url> -v           # show progress + depth
crawl-sitemap <url> --depth 2    # limit crawl depth
```

### Vendored Dependencies

`bin/vendor` — Go CLI for managing external dependencies built from source with review-gated updates. Dependencies are cloned into `vendor/`, built locally, and symlinked to `~/.local/bin/`.

```bash
vendor add <name> <url> --ref <tag>   # Clone and register a dependency
vendor list                            # Show all vendored deps
vendor build <name>                    # Build from source
vendor install <name>                  # Build + symlink binary
vendor approve <name>                  # Approve current state after review
```

**Key files:**
- `vendor/MANIFEST.json` — Dependency registry (tracked in git)
- `vendor/*/` — Cloned repos (gitignored)
- `cmd/vendor/` — CLI source code (Go, stdlib only)
- `fish/conf.d/vendor_check.fish` — Weekly update check on shell startup

**Install script:** `./install vendor` builds the CLI and runs `vendor install` for all entries.

### Process Labeling

`bin/proc-label` sets custom process names in Activity Monitor using Python's `setproctitle` — the only method that works on macOS (exec -a, Ruby setproctitle, and symlinks only affect `ps`). See [docs/proc-label.md](docs/proc-label.md).

## Detailed Documentation

| Document | Contents |
|----------|----------|
| [docs/fish.md](docs/fish.md) | Fish shell conf.d, functions, fzfm, plugins |
| [docs/neovim.md](docs/neovim.md) | Neovim plugins, LSP, keymaps, settings |
| [docs/hammerspoon.md](docs/hammerspoon.md) | Seeds, hotkeys, VPC system, Spoons |
| [docs/services.md](docs/services.md) | LaunchAgents, VPC workspaces, bin utilities |
| [docs/vpc-schema.md](docs/vpc-schema.md) | VPC file format specification |
| [docs/astro.md](docs/astro.md) | Astrological transit tracker CLI |
| [docs/proc-label.md](docs/proc-label.md) | Process labeling for Activity Monitor |

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
