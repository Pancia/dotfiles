# Neovim Configuration

## Overview

- **Configuration Style**: Hybrid Vimscript + Lua
- **Entry Point**: `/Users/anthony/dotfiles/nvim/init.vim` (loads init.lua at the end)
- **Plugin Manager**: vim-plug
- **Primary Use Cases**: Clojure development (Conjure + REPL), general text editing
- **VSCode Integration**: Configuration includes conditional blocks for VSCode Neovim extension

## Directory Structure

```
nvim/
├── init.vim              # Main entry point (Vimscript)
├── init.lua              # Lua initialization (loaded last)
├── plugins.vim           # Plugin declarations and vim-plug setup
├── settings.vim          # Core Neovim settings
├── mappings.vim          # General key mappings
├── theme.vim             # Theme and syntax highlighting
├── autogroups.vim        # Autocommands (auto-save, cursor position, etc.)
├── syntax.vim            # Syntax customizations
├── local.vim             # Local machine-specific overrides
├── lua/                  # Lua modules
│   ├── lsp.lua           # Legacy LSP config (deprecated)
│   └── plugs/            # Plugin configurations in Lua
│       ├── hop.lua       # Hop motion plugin config
│       ├── lsp.lua       # Active LSP config (clojure_lsp)
│       └── cmp.lua       # nvim-cmp completion config
├── plugs/                # Plugin configurations in Vimscript
│   ├── conjure.vim       # Clojure REPL integration
│   ├── fzf.vim           # Fuzzy finder setup
│   ├── lsp.vim           # LSP key mappings
│   ├── git.vim           # Git-related plugin configs
│   ├── sexp.vim          # S-expression editing for Clojure
│   ├── vimwiki.vim       # Wiki/note-taking config
│   └── [30+ other configs]
├── ftplugin/             # Filetype-specific configurations
│   ├── clojure.vim       # Clojure-specific settings
│   ├── javascript.vim    # JavaScript settings
│   ├── vim.vim           # Vimscript settings
│   └── [13+ other filetypes]
└── after/
    └── ftplugin/
        └── clojure.vim   # Post-load Clojure overrides
```

## Configuration Loading Order

1. **init.vim** sources files in this order:
   - `plugins.vim` - Plugin declarations
   - `autogroups.vim` - Autocommands
   - `mappings.vim` - Key mappings
   - `settings.vim` - Core settings
   - `theme.vim` - Theme (if not VSCode)
   - `syntax.vim` - Syntax highlighting (if not VSCode)
   - `local.vim` - Local overrides
   - `init.lua` - Lua initialization

2. **plugins.vim** auto-sources all files in `plugs/` directory

3. **init.lua** requires:
   - `plugs/hop` (motion plugin)
   - `plugs/lsp` (LSP setup)
   - `plugs/cmp` (completion setup)

## Plugin Management

### Plugin Manager: vim-plug

- **Auto-installation**: Automatically installs vim-plug if missing
- **Location**: `~/.config/nvim/autoload/plug.vim`
- **Plugins Directory**: `~/.config/nvim/plugged/`

### Plugin Categories

| Category | Plugins | Purpose |
|----------|---------|---------|
| **Essentials** | vim-repeat, vim-surround, vim-speeddating, vim-better-whitespace | Core text editing enhancements |
| **Movement** | hop.nvim, vim-easymotion | Fast cursor navigation |
| **Fuzzy Finding** | fzf, fzf.vim, telescope.nvim | File/buffer/text search |
| **LSP** | nvim-lspconfig, fzf-lsp.nvim | Language Server Protocol support |
| **Completion** | nvim-cmp, cmp-nvim-lsp, cmp-buffer, cmp-path, cmp-conjure | Autocompletion |
| **Clojure** | conjure, vim-sexp, vim-clojure-static, cmp-conjure | Clojure REPL-driven development |
| **Git** | vim-fugitive, vim-gitgutter, conflict-marker.vim | Git integration |
| **UI** | vim-airline, undotree, vim-which-key, vim-illuminate | Interface enhancements |
| **Theme** | onedark.vim, nvim-colorizer.lua | Color scheme and color highlighting |
| **File Browser** | vimfiler.vim | Directory/file navigation |
| **Language Support** | vim-svelte-plugin, semshi (Python), fennel.vim, vim-gdscript3 | Language-specific features |

### Managing Plugins

Quick commands via semicolon prefix (`;p`):

| Command | Action |
|---------|--------|
| `;pi` | Install plugins |
| `;pc` | Clean unused plugins |
| `;pu` | Update plugins |
| `;po` | Open plugins.vim |
| `;ps` | Plugin status |
| `;pd` | Plugin diff |

## Key Features

### LSP Configuration

**Supported Language Servers:**
- `clojure_lsp` - Clojure Language Server

**LSP Key Mappings:**

| Mapping | Action |
|---------|--------|
| `gd` | Go to definition |
| `K` | Show hover documentation |
| `gD` | Go to declaration |
| `gi` | Go to implementation |
| `[d` / `]d` | Navigate diagnostics |
| `,de` | Show diagnostic float |
| `,dq` | Send diagnostics to location list |

**LSP Semicolon Commands (`;s`):**

| Command | Action |
|---------|--------|
| `;s?` | LSP Info |
| `;sR` | LSP Restart |
| `;sa` | Code actions |
| `;sd` | Show definitions |
| `;si` | Show implementations |
| `;su` | Show references |
| `;sf` | Document symbols |
| `;sw` | Workspace symbols |
| `;sg` | Buffer diagnostics |
| `;sG` | All diagnostics |

### Completion (nvim-cmp)

**Sources:**
1. LSP completions (`nvim_lsp`)
2. Conjure REPL completions (`conjure`)
3. Buffer text (`buffer`)
4. File paths (`path`)

**Completion Mappings:**

| Mapping | Action |
|---------|--------|
| `Ctrl-n` / `Ctrl-p` | Navigate completion menu |
| `Tab` / `Shift-Tab` | Select next/previous item |
| `Ctrl-Space` | Trigger completion |
| `Ctrl-e` | Close completion menu |
| `Enter` | Confirm selection |
| `Ctrl-d` / `Ctrl-f` | Scroll documentation |

### Movement (Hop.nvim)

Hop provides EasyMotion-like navigation:

| Mapping | Action |
|---------|--------|
| `Space w` | Jump to word forward |
| `Space b` | Jump to word backward |
| `Space j` | Jump to line forward |
| `Space k` | Jump to line backward |
| `f` / `F` | Hop to character forward/backward |
| `t` / `T` | Hop to before character forward/backward |

### Fuzzy Finding (FZF)

**Primary Mapping:**
- `Ctrl-P` - Smart fuzzy find (Git files in repo, otherwise all files with parent navigation)

**FZF Commands (`;f`):**

| Command | Action |
|---------|--------|
| `;ff` | Find files |
| `;fg` / `;fp` | Project/Git files |
| `;fb` | Open buffers |
| `;fh` | Search help tags |
| `;fm` | Search key mappings |
| `;fk` | Search marks |
| `;fw` | Search windows |
| `;fHf` | File history |
| `;fH:` | Command history |
| `;fH/` | Search history |

**Custom Features:**
- `Ctrl-P` in file browser to navigate to parent directory
- 50% height window with preview pane (toggle with `Ctrl-/`)

### Clojure Development (Conjure)

**Configuration:**
- HUD size: 50% width × 50% height
- Log wrapping enabled
- No syntax highlighting in log
- Custom test runners for `deftest` and `specification`

**Key Mappings:**
- `k` - Show documentation for word under cursor
- `gd` - Go to definition
- Evaluate code directly in REPL with Conjure commands

**Fennel Support:**
- Fennel client using `hs-fennel` command (Hammerspoon Fennel)

### Git Integration

**Plugins:**
- vim-fugitive - Git commands
- vim-gitgutter - Show git diff in sign column
- conflict-marker.vim - Conflict resolution

### Theme & Appearance

**Color Scheme:** onedark.vim with custom overrides

**Adaptive Theme:**
- Automatically detects macOS light/dark mode
- Custom color palette for light mode
- Different `@variable` highlighting based on system appearance

**Custom Highlights:**
- Project keywords: `TODO`, `TASK`, `NOTE`, `FIXME`, `LANDMARK`, `CONTEXT`, `TRANSLATE`, `RESUMEHERE`
- Search highlighting with yellow on black
- Custom Pmenu (popup menu) and floating window backgrounds

### Custom Keymaps

**Navigation:**

| Mapping | Action |
|---------|--------|
| `Ctrl-j` / `Ctrl-k` | Previous/Next buffer |
| `BS` / `Shift-BS` | Jump backward/forward in cursor history (centered) |
| `n` / `N` / `*` / `#` | Search and center screen |
| `Y` | Yank to end of line (like `D`, `C`) |
| `U` | Redo (opposite of `u`) |

**Disabled:**
- Arrow keys (enforces hjkl navigation)
- `Enter` in normal mode

**Terminal:**
- `Esc` exits terminal mode (except in FZF)
- `!` prefix for shell commands

**Search:**
- `Ctrl-e` - Clear search highlighting

### Auto-Commands

**Auto-Save:**
- Triggers on: `CursorHold`, `InsertLeave`, `TextChanged`
- Skips Conjure log buffers
- Shows timestamp when files are saved

**Cursor Position:**
- Restores last cursor position on file open
- Searches for `RESUMEHERE` marker first
- Falls back to mark `"` position

**Fold Persistence:**
- Automatically saves/restores folds
- Stores only cursor position and folds (not mappings)

**Terminal Behavior:**
- Sets `bufhidden=hide` for terminals
- Redraws on terminal open

**File Type Detection:**
- `*.wiki` → vimwiki
- `*.vpc` → json

### Which-Key Integration

Two prefix systems for discoverable commands:

1. **Semicolon (`;`)** - Primary command prefix
   - `;p` - Plugin management
   - `;s` - LSP commands
   - `;f` - FZF commands
   - `;h` - Help tags
   - `;;` - Show all commands

2. **Comma (`,`)** - Secondary prefix
   - `,de` - Diagnostic float
   - `,dq` - Diagnostic location list

## Core Settings

### Editor Behavior

| Setting | Value | Purpose |
|---------|-------|---------|
| `mouse` | `a` | Enable mouse in all modes |
| `number` | enabled | Show line numbers |
| `cursorline` | enabled | Highlight current line |
| `expandtab` | enabled | Use spaces instead of tabs |
| `shiftwidth` / `tabstop` | 4 | Default indentation |
| `foldmethod` | `indent` | Fold based on indentation |
| `foldlevelstart` | 99 | Start with all folds open |

### File Handling

| Setting | Value |
|---------|-------|
| `nobackup` | enabled |
| `noswapfile` | enabled |
| `undofile` | enabled |
| `undodir` | `~/.config/nvim/undo/` |
| `undolevels` | 500 |

### Interface

| Setting | Value |
|---------|-------|
| `termguicolors` | enabled |
| `visualbell` | enabled (no beeping) |
| `showtabline` | 2 (always) |
| `title` | enabled |
| `wildmode` | `list:longest,full` |
| `terminal_scrollback_buffer_size` | 10000 |

## File Locations

### Configuration Files

| Purpose | Location |
|---------|----------|
| Main entry | `/Users/anthony/dotfiles/nvim/init.vim` |
| Lua init | `/Users/anthony/dotfiles/nvim/init.lua` |
| Plugins | `/Users/anthony/dotfiles/nvim/plugins.vim` |
| Settings | `/Users/anthony/dotfiles/nvim/settings.vim` |
| Mappings | `/Users/anthony/dotfiles/nvim/mappings.vim` |
| Theme | `/Users/anthony/dotfiles/nvim/theme.vim` |

### Runtime Directories

| Purpose | Location |
|---------|----------|
| Lua modules | `/Users/anthony/dotfiles/nvim/lua/` |
| Plugin configs (Vimscript) | `/Users/anthony/dotfiles/nvim/plugs/` |
| Plugin configs (Lua) | `/Users/anthony/dotfiles/nvim/lua/plugs/` |
| Filetype plugins | `/Users/anthony/dotfiles/nvim/ftplugin/` |
| Post-load overrides | `/Users/anthony/dotfiles/nvim/after/ftplugin/` |
| Installed plugins | `~/.config/nvim/plugged/` |
| Undo history | `~/.config/nvim/undo/` |

### Symlink Setup

The configuration automatically creates symlinks from `~/dotfiles/nvim/ftplugin/` to `~/.config/nvim/ftplugin/` to ensure filetype plugins are properly loaded.

## VSCode Integration

When running with VSCode Neovim extension (`g:vscode` is set):

**Disabled:**
- All UI plugins (airline, which-key, undotree, etc.)
- LSP and completion
- Theme and syntax highlighting
- File browser plugins

**Enabled:**
- Core editing plugins (surround, repeat, etc.)
- Movement plugins (hop, easymotion)
- FZF and vimwiki
- Git plugins

## Special Features

### Welcome Screen

When opening Neovim without a file, displays:
```
Welcome back Commander! o7
```

### Smart Fuzzy Find

`Ctrl-P` behavior:
- Inside git repo → Shows git-tracked files
- Outside git repo → Shows all files with ability to navigate parent directories

### Project Keywords

Custom syntax highlighting for project management keywords:
- `TODO` - Purple, standout
- `TASK` - Red, standout
- `NOTE` - Cyan, standout
- `FIXME` - Yellow on white, standout
- `LANDMARK` - Green, standout
- `CONTEXT` - Pink, standout
- `TRANSLATE` - Magenta, standout
- `RESUMEHERE` - Blue on light gray, standout (also restores cursor position)

### Dev Environment Functions

Custom helper function for Clojure development:
- `RunCLJDevEval()` - Evaluates code in a development namespace
- Configurable via `g:clj_dev_ns` and `g:clj_dev_cmd_suffix`
