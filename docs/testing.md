# Testing: components

| Component | Alias | Runner | Notes |
|---|---|---|---|
| `services/youtube_transcribe` | `yt` | pytest | needs fastapi/httpx/etc. |
| `services/server_check` | `server-check` | pytest | fakes the server's SSH answer; parses `show.sh`, never runs it |
| `lib/python` | `python` | pytest | |
| `lib/lua` | `lua`, `hammerspoon` | pytest | runs Hammerspoon seeds (copylink, rolevote) under `lua5.4` with a stub `hs` (`tests/lib/lua/harness.lua`), calling their URL handlers directly; skips without `lua5.4` |
| `bin/astro` | `astro` | pytest | needs kerykeion/pyswisseph |
| `bin/ytdl` | `ytdl` | pytest | stubs yt-dlp via PATH |
| `bin/exocortex-id` | `exocortex` | pytest | |
| `fish` | — | pytest | **pytest, not fishtape** — drives `fish --no-config`, with `-c`, or for the revive tests interactive in a real pty; needs the `fish` binary. Each pty test waits 2.6 s for fish to start, so the whole component takes about 3 min, longer than the Bash tool's 2 min default timeout. Run one file when you can (`cmds test fish/test_trash.py`), and give a full run a longer timeout |
| `hooks` | — | pytest | runs `rcs/claude-ensure-rcs-hook.sh` |
| `roleplay` | `roleplay` | pytest | drives the bash script as a subprocess; no deps. Tests live in `roleplay/tests/`, reached via the `tests/roleplay` symlink |
| `svc` | `supervise`, `svc-tmux` | pytest | needs `pyte` (+ `tmux`, else those tests skip). pty-rendered status bar, orphan checks via `ps`, a private tmux socket per test |
| `mods` | `roleplay-bookends` | pytest | `tests/mods/test_mod_suites.py` runs `claude plugin test` on each `ai/mods/*/` folder that has `tests/`; skips without `claude`. The tests themselves are `*.test.ts(x)` beside each mod. See [ai/mods/README.md](../ai/mods/README.md) |

`busted` and `fishtape` runners exist in `RUNNERS` but no component uses them.

Each component runs as its own `pytest` subprocess, so the run ends with an
**aggregate summary** naming every component, its counts, and one overall
PASSED/FAILED verdict. Without it the output just ends in the last component's
tally and reads as though nothing else ran — a real reader once saw astro's `107
passed` and concluded the other 300 tests hadn't executed.

`DOTFILES` is derived from `__file__`, not `$HOME/dotfiles`, so a clone or worktree
elsewhere tests itself; the resolved root is printed at the top of every run.
