# Fish Shell Configuration

## Overview

Fish is the primary shell for this dotfiles setup (migrated from Zsh). The configuration includes:

- **Auto-setup**: RC files are automatically symlinked to `~/.config/fish/`
- **conf.d loading**: Configuration snippets loaded automatically on shell startup
- **Fisher plugins**: Plugin manager with curated plugins installed automatically

## conf.d/ Files

Configuration snippets that run on shell initialization:

| File | Purpose |
|------|---------|
| `path.fish` | PATH setup (dotfiles/bin, local bin, user binaries) |
| `brew.fish` | Homebrew environment initialization |
| `pyenv.fish` | Python version manager setup |
| `asdf.fish` | Universal version manager initialization |
| `ruby.fish` | Ruby environment configuration |
| `node.fish` | Node.js environment setup |
| `java.fish` | Java environment configuration |
| `clojure.fish` | Clojure development setup |
| `bat.fish` | Bat theme configuration (GitHub theme) |
| `git.fish` | Git settings (`GIT_EDITOR=nvim`) |
| `fzfm_keybindings.fish` | Vim-style leader key (Ctrl+S) for fuzzy finding |
| `my_fzfm_settings.fish` | Custom fzfm jump commands and frecency settings |

## Key Functions (fish/functions/)

The `fish/functions/` directory contains 169 function files. Key functions include:

### Directory Navigation & Bookmarks
- **`d.fish`**: Directory bookmarks system (Ruby-backed)
- **`q.fish`**: Command registry and quick access (Ruby-backed)
- **`z.fish`**: Jump to frequently/recently used directories
- **`chpwd.fish`**: Directory change hooks (shows TODOs, updates cache, manages history)

### Interactive Search & Fuzzy Finding
- **`fzfm_leader.fish`**: Interactive fzf menu with multiple search modes
- **`fzf_complete.fish`**: Fuzzy completion integration
- **`fzf_cd.fish`**: Fuzzy directory changing

### Development Tools
- **`ai_git_commit.fish`**: AI-powered Git commit message generation
- **`git_helper.fish`**: Git workflow utilities
- **`dev_helper.fish`**: Development environment helpers

### System Utilities
- **`ls.fish`**: Wraps `ls -h` for human-readable output
- **`file_helper.fish`**: File manipulation utilities
- **`system_helper.fish`**: System information and management

## fzfm Leader Key System

Interactive fuzzy finder triggered by **Ctrl+S**.

### Available Modes

| Key | Mode | Description |
|-----|------|-------------|
| `Space` | Quick search | Fast file search in current context |
| `s` | All files | Search all files in directory tree |
| `f` | Frecent | Search recent + frequent files (frecency algorithm) |
| `r` | Recent | Search recently accessed files |
| `g` | Grep | Search file contents with ripgrep |
| `d` | Directory | Search and navigate directories |
| `a` | Thorough | Deep search including hidden files |
| `q` | Exit | Close the fzfm menu |

### Custom Jump Commands

Configured in `my_fzfm_settings.fish` for quick navigation to common directories.

## Fisher Plugins

Managed via [Fisher](https://github.com/jorgebucaran/fisher) plugin manager:

| Plugin | Purpose |
|--------|---------|
| `jorgebucaran/nvm.fish` | Node version manager for Fish |
| `franciscolourenco/done` | Desktop notifications for long-running commands |
| `ilancosman/tide` | Fast async prompt with Git integration |
| `patrickf1/fzf.fish` | Fuzzy finder integration (Ctrl+R history, Ctrl+Alt+F files) |
| `~/projects/tooling/fzfm` | Custom frecency-based file manager |

## File Locations

### Primary Configuration
- **Main config**: `fish/config.fish` → `~/.config/fish/config.fish`
- **Functions**: `fish/functions/` (169 files) → `~/.config/fish/functions/`
- **conf.d**: `fish/conf.d/` (18 files) → `~/.config/fish/conf.d/`
- **Completions**: `fish/completions/` → `~/.config/fish/completions/`

### Configuration Structure
```
fish/
├── config.fish           # Main configuration file
├── conf.d/              # Auto-loaded configuration snippets (18 files)
├── functions/           # Function definitions (169 files)
└── completions/         # Command completions
```

## Key Features

### Auto-loading
Fish automatically loads:
- All files in `conf.d/` on shell startup
- Functions on-demand from `functions/` directory (lazy loading)
- Completions for installed commands

### Environment Management
- **PATH management**: Centralized in `path.fish`
- **Language versions**: Multiple version managers (pyenv, asdf, nvm)
- **Homebrew integration**: Automatic environment setup

### Developer Experience
- **Syntax highlighting**: Built-in, no plugin needed
- **Autosuggestions**: Built-in history-based suggestions
- **Tab completions**: Extensive command-specific completions
- **Git integration**: Status in prompt, commit helpers

## Migration Notes

This setup represents a migration from Zsh to Fish. Key changes:
- Fish-native syntax (no POSIX shell compatibility layer needed)
- Lazy function loading instead of sourcing all files at startup
- Built-in features replace many Zsh plugins
- Fisher replaces Oh-My-Zsh/Prezto plugin management
