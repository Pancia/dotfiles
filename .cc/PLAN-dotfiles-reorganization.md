# Dotfiles Reorganization Options

## Current State Summary

Your dotfiles have ~700+ files across 26 directories. The core tools (Fish, Neovim, Hammerspoon) are well-organized, but there's accumulated cruft:
- Deprecated `_zsh/` and `antigen/` directories
- Unstructured `bin/` (59 mixed scripts)
- Catch-all `misc/` directory
- Planning files scattered at root

## Layout Options

### Option A: Minimal Cleanup (Least Disruptive)

Just archive dead code and consolidate clutter. Keep current structure intact.

```
dotfiles/
├── _archive/           # Move _zsh/, antigen/, vimlocal/ here
├── plans/              # Move PLAN-*.md files here
├── fish/               # (unchanged)
├── nvim/               # (unchanged)
├── lib/                # (unchanged)
├── bin/                # (unchanged, maybe add categories later)
├── rcs/                # (unchanged)
└── ...
```

**Pros**: Minimal risk, quick win, preserves muscle memory
**Cons**: Doesn't address deeper structural issues

---

### Option B: XDG-Aligned Structure

Reorganize to match XDG Base Directory Specification conventions (`~/.config/`, `~/.local/`).

```
dotfiles/
├── config/             # Everything that goes to ~/.config/
│   ├── fish/
│   ├── nvim/
│   ├── hammerspoon/
│   ├── karabiner/
│   ├── ghostty/
│   └── kitty/
├── local/
│   ├── bin/            # User scripts -> ~/.local/bin
│   └── share/          # Data files -> ~/.local/share
├── lib/                # Shared libraries (not symlinked)
├── services/           # LaunchAgents
└── install             # Updated to symlink config/ and local/
```

**Pros**: Standard, predictable, many tools expect this
**Cons**: Major restructure, breaks your rcs/ metadata system

---

### Option C: Stow-Compatible Packages

Each "package" is a self-contained unit that GNU Stow can symlink.

```
dotfiles/
├── fish/
│   └── .config/fish/   # Stow creates ~/.config/fish
├── nvim/
│   └── .config/nvim/
├── hammerspoon/
│   └── .hammerspoon/
├── bin/
│   └── .local/bin/
├── services/
│   └── Library/LaunchAgents/
└── stow.sh             # Simple: stow -t ~ fish nvim hammerspoon
```

**Pros**: Industry standard, easy to share individual packages
**Cons**: Extra nesting, replaces your custom rcs/ system

---

### Option D: Function-Based Grouping

Organize by purpose rather than tool.

```
dotfiles/
├── shell/              # Fish config + shell utilities
├── editor/             # Neovim + editor tools
├── automation/         # Hammerspoon + scripts + services
├── apps/               # App configs (karabiner, ghostty, etc.)
├── lib/                # Language libraries
├── data/               # Wiki, prompts, templates
└── install
```

**Pros**: Conceptually clear, reduces directory count
**Cons**: Breaks tool conventions, harder for others to navigate

---

### Option E: Keep Current + Categorize Bin

Your current structure is fine. Just clean up the two messy areas.

```
dotfiles/
├── _archive/           # Dead code (zsh, antigen, vimlocal)
├── bin/
│   ├── media/          # music, ytdl, transcribe
│   ├── system/         # vpc, window-switcher, app-launcher
│   ├── dev/            # git helpers, build tools
│   └── misc/           # everything else
├── misc/ -> _archive/  # Or just delete
└── (rest unchanged)
```

**Pros**: Targeted improvement, low risk
**Cons**: Doesn't simplify top-level complexity

---

## Key Tradeoffs to Consider

### Your rcs/ Metadata System vs. Stow

| Aspect | Your rcs/ System | GNU Stow |
|--------|------------------|----------|
| Learning curve | You already know it | Industry standard, others know it |
| Flexibility | Any destination path via header | Must mirror home directory structure |
| Portability | Custom (needs your script) | Works on any Unix system with Stow |
| Shareability | Others need your tooling | Drop-in for anyone using Stow |

**Bottom line**: Your system is more flexible (can map `rcs/foo` to any path), Stow is more portable. Neither is clearly better - depends on whether you ever share configs.

### Flat vs. Nested bin/

Currently 59 scripts in one flat directory. Options:
- **Keep flat**: Simple, `which foo` always works, no PATH complexity
- **Categorize**: `bin/media/`, `bin/dev/`, etc. - cleaner but need to add subdirs to PATH

Most dotfiles repos keep bin/ flat. It's only worth categorizing if you struggle to find scripts.

### Top-level Directory Count

You have 26 top-level directories. Some popular approaches:
- **Minimal** (5-8 dirs): fish, nvim, hammerspoon, bin, config, lib, install
- **Verbose** (15-25 dirs): One per tool, separate docs, services, vpc, etc.

Your current structure leans verbose but it's organized. No need to consolidate unless navigation feels painful.

## What's Actually Worth Doing

If you ever want to act on this, the low-effort wins are:
1. Archive `_zsh/`, `antigen/`, `vimlocal/` to `_archive/`
2. Move `PLAN-*.md` files to `plans/` or delete them
3. Clean out `misc/` (decide per-project: keep, archive, or delete)

Everything else is optional restructuring with unclear ROI.
