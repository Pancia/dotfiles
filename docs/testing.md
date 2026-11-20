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

## Isolation

The runner (`lib/python/run_tests.py`) starts every pytest with a throwaway home
and an environment built from the real one. It does this in `run_pytest`, so it
covers every component, every file or node id you name, and `cmds test` exactly
as it covers `uv run lib/python/run_tests.py`. It is not a conftest fixture: a
fixture would miss `roleplay` (reached through the `tests/roleplay` symlink) and
paths a test module computes at import time.

**The home.** `test_home()` makes a `dotfiles-test-home-*` folder in the system
temp folder and removes it when the pytest ends. It holds:

- `dotfiles`, a symlink to the tree under test. Scripts hard-code
  `$HOME/dotfiles` (for example `MANIFEST=` in `rcs/claude-ensure-rcs-hook.sh`),
  so they read the clone, not the live checkout;
- `.config/`, `.local/share/`, `.local/state/` and `.cache/`;
- `.gitconfig` with a test identity and `init.defaultBranch = master`;
- `.config/jj/config.toml` with the same identity in a `[user]` table.

**What is set** (`isolated_env`):

- `HOME`, and `XDG_CONFIG_HOME`, `XDG_DATA_HOME`, `XDG_STATE_HOME`,
  `XDG_CACHE_HOME` at their standard paths under it. Code that hard-codes
  `~/.local/state/...` (as `lib/python/ccjj.py` does) lands in the same place;
- `GIT_CONFIG_GLOBAL` (the test `.gitconfig`) and `GIT_CONFIG_NOSYSTEM=1`. This
  also drops the live `core.hooksPath` from `rcs/gitconfig`, so git tests run no
  live hooks;
- `JJ_CONFIG`, `JJ_USER` and `JJ_EMAIL`;
- `UV_CACHE_DIR` and `UV_PYTHON_INSTALL_DIR`, pinned to the real folders;
- `PATH`, with the tree's own `bin/` first and every other `dotfiles/bin` folder
  removed (see below).

**What is removed:** `TMUX`, `TMUX_PANE`, `ITERM_SESSION_ID`, `TERM_SESSION_ID`,
`CLAUDECODE`, `SVC_FS_CONFIG`, `SVC_TMUX_SOCKET`, and every variable whose name
starts with `CLAUDE_`, `CCS_` or `CC_JJ_`. A run inside tmux, iTerm or a Claude
session behaves like one outside them. Every other variable is kept.

**The `PATH` rule.** The live `~/dotfiles/bin` is on the operator's `PATH`, so a
test that runs a dotfiles command by bare name would test the live copy, even
from a clean clone. The runner puts `<tree>/bin` first and drops any entry whose
last two parts are `dotfiles/bin`, or that is (or resolves to) the real home's
`dotfiles/bin`. Tests no longer need to guard against this by hand.

**Why uv is pinned.** uv finds its cache and its Python installs under `HOME`.
Under the throwaway home it would start empty and download every `--with`
dependency, and the astro helpers' `uv run --with git+https://…` packages, on
every run. The runner reads the real folders once, before `HOME` moves: an
existing `UV_CACHE_DIR` or `UV_PYTHON_INSTALL_DIR` first, else `uv cache dir`
and `uv python dir`. There is no `~/.config/uv/uv.toml` on this machine, so
nothing else of uv's is lost; if one is added and the suite needs it, pass it on
with `UV_CONFIG_FILE`.

**Opting out.** A `COMPONENTS` entry may set `"isolation": False` with an
`"isolation_reason"` string. Its pytest then inherits the environment, and the
runner prints `isolation off: <reason>`. Use it only for a component that cannot
run otherwise, and list the component and its reason here. No component opts out
yet.

Checked under isolation and needing no opt-out (row REST-A):

- `roleplay`: each test passes its own `tmp_path` home to the scripts it runs,
  and `test_roll_sees_a_throwaway_home` pins that. The shared home for `run()`
  comes from `tmp_path_factory`, so no folder leaks;
- `mods`: `claude plugin test` runs each mod's test files with no fs, network or
  process access, so the throwaway home changes nothing. It needs `claude` on
  `PATH`; without it the suites skip;
- `lib/lua`: `harness.lua` takes its own paths. It needs `lua5.4`; without it
  every test skips.

**Interim red** (row ISOLATE of the hermetic-test-suite spec added the isolation):
after this row merges, `hooks`, `astro` and `roleplay` fail under `cmds test` until HOOKS, ASTRO and REST-A land.
Those components still read the live checkout or the real home, and each of those
rows makes its component pass under isolation.
