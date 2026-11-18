# Claude Code themes that follow macOS light and dark

Claude Code uses the custom theme `custom:dark-light-term` (set in
`rcs/claude-settings.json`). Its live file is
`~/.claude/themes/dark-light-term.json`. It is not in `rcs/MANIFEST`: it is a
copy that `bin/claude-theme-sync` writes, and that copy changes with the time
of day.

Why: an expanded tool call in focus view is painted with
`userMessageBackgroundHover`, but most of its text has no color of its own, so
it takes the terminal's default color. The iTerm profile switches its colors
with the macOS appearance: black text by day, light gray text at night. One
fixed box color cannot suit both, and `/theme auto` would use Claude Code's
Light theme by day, which was rejected.

- `dark-light-term.day.json`: the dark theme with a light gray box, for black text.
- `dark-light-term.night.json`: the plain dark theme, whose box is dark gray.

The Hammerspoon seed `claudetheme` (`lib/lua/seeds/claudetheme.lua`) runs
`claude-theme-sync` at start and on each appearance change. Claude Code watches
`~/.claude/themes/` and redraws running sessions when the file changes, with no
restart (tested 2026-11-17).

Edit the two files here, never the live copy, then run `claude-theme-sync`.
