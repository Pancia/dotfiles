# Hermes commands (`Cmd+Space`)

Hermes is a which-key app launcher. Commands are defined in `rcs/hermes-commands.json`.

**Command types:**
- `"shell command"` — runs and closes
- `{"shell": "command"}` — opens in terminal, closes on exit
- `{"interactive": "command"}` — opens in terminal, stays open when done
- `{"shell:fish": "command"}` — runs via fish shell

**Submenu keys:** Objects with `"_desc": "+name"` create submenus. `"_stay": true` keeps the menu open after running a command (used for music controls).

**Generators:** `"generator:name"` dynamically builds a submenu (snippets, services, vpc).

**Reserved root keys — never assign these in JSON.** They are hardcoded in the Hermes source
(`~/projects/hermes/Sources/Hermes/HermesViewController.swift`) and **silently override** any
JSON entry with the same key — `withBuiltins` merges with the builtin winning, and `keyDown`
intercepts them before the menu is even consulted:

| Key | Reserved for | Scope |
|-----|--------------|-------|
| `a` | `+apps` mode (built-in app switcher) | root only |
| `w` | `+windows` mode (built-in window switcher) | root only |
| `:` | search mode | every level |

Escape / Backspace / Return / arrow keys are also intercepted. A duplicate key fails *silently* —
the entry renders nowhere and nothing is logged — so check `rcs/hermes-commands.json`'s `_note`
block (which lists currently-free root keys) before adding a top-level menu.

The root keyspace is nearly full, so **one-off scripts go in `x` (+utils)** rather than claiming a
root letter. Reserve new root keys for menus that will hold several related entries.

**Comments:** JSON has none, but the parser skips any key beginning with `_`, so a `"_note"` key
holding an array of strings works as a comment block at any level.

**Reloading:** no rebuild needed for config edits — `CommandLoader.load()` re-reads
`~/.config/hermes/commands.json` on every launcher open (background refresh pass), so the first
open after an edit may show the cached menu and the next one is current. `rebuild-hermes`
(`Cmd+Space` → `h` → `r`) is only for Swift source changes.
