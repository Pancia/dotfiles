# Spec: Green, hermetic test suite for the merge gate

**Date**: 2026-11-19
**Status**: draft
**Workflow**: dotfiles-dev

## Overview

This spec makes the dotfiles test suite pass, and makes it hermetic, so it can become the merge gate: `alt heavy run --label dotfiles-test -- uv run lib/python/run_tests.py`, first in observe mode and later in enforce mode. It comes from the operator's goal statement, which reports a full run on `master` 1898647d. That run took about 14 minutes and showed three failure groups. The goal also asks for:

- an audit of every component in `COMPONENTS`;
- a clean-clone run outside `~/dotfiles`;
- a ruling on whether the gate needs a faster target.

This spec was checked against `master` at **1898647d** ("whisper-serverd: reap the warm server after 30s idle"). The checklist (`altera/prompts/dotfiles-dev/checklist.md`) is **not on `master` yet**. It exists only on the unmerged commit f5db1a2. This spec applies the ten items as the brief gives them. No test was run while writing this spec, because the permission to run tests was refused. Every cause below comes from reading the code. Each row's done check shows whether its cause was right.

**Causes found**

1. **Astro zodiacal-releasing tests (32 errors).** `ZRCalculator._birth_payload` in `bin/astro` (class at line 2954, `HELPER = "astro-zr-helper"` at 2957) sends only `city` and `nation`. It drops the `lat`, `lng` and `tz_str` that the test fixture supplies. `_build_chart` in `bin/astro-zr-helper` (lines 181–200) then passes `"Provo, US"` as a string to stellium's `ChartBuilder.from_details`, which geocodes it over the network with Nominatim. Stellium's `Native._process_location` skips the geocoder for a dict that has `latitude`, `longitude` and `timezone`, and it then calls no timezone lookup either. A second fault: `tests/bin/astro/conftest.py:29` (`astro_module`) loads `Path.home() / "dotfiles" / "bin" / "astro"`. That is the live checkout, not the tree under test.
2. **Revive test.** `TestThisPane::test_a_pane_whose_last_shell_only_ran_revive_speaks_for_the_real_ghost` (`tests/lib/python/test_revive.py:400`) uses the `store` fixture, not `in_pane`. So it does not clear `TMUX`. When the suite runs inside tmux, `this_pane_key()` (`lib/python/revive.py:239`) appends `-<TMUX_PANE>`, no ghost matches, and `cmd_get("here")` returns 1. This is a test bug (likely, not yet confirmed).
3. **svc tests.** `bin/supervise:268` sets `in_tmux=1` when `TMUX` is set. Then `q` stops the service but keeps the supervisor running. `test_keys_restart_suspend_resume_quit` (line 204) and `test_bar_separator_and_panel_render` (line 236) start `supervise` with the inherited environment and expect `q` to exit 0. Inside tmux they hang, then fail. This is a test bug (likely, not yet confirmed). `test_clean_exit_closes_the_window_crash_keeps_it` (line 770) is **not explained**:
   - its `tmux_env` fixture already drops `TMUX`;
   - `cmd_stop` (`bin/svc:212`) sends TERM, and `supervise` exits 0 on TERM (lines 223–230);
   - so `remain-on-exit failed` (`lib/svc/tmux.conf:18`) should close the window.

   This test gets its own diagnose-first row.
4. **Real home.** No component isolates `HOME`: `tests/conftest.py` sets no environment. Details are under "Audit results" in Technical Approach.

**Binding decisions**

- Isolation lives in the **runner**: `run_pytest` in `lib/python/run_tests.py` gives each component's pytest a throwaway `HOME`. A conftest fixture is not used. The runner covers every component the same way. That includes `roleplay`, which is reached through the `tests/roleplay -> ../roleplay/tests` symlink. It also covers paths that a test module computes at import time, such as `TestJsonParsing.DST`. Each test still owns its own environment where a row says so.
- The throwaway `HOME` holds a `dotfiles` symlink to the tree under test. Scripts that hard-code `$HOME/dotfiles` then test the clone, not the live checkout. One example is `rcs/claude-ensure-rcs-hook.sh` (`MANIFEST="$HOME/dotfiles/rcs/MANIFEST"`).
- `uv`'s cache and Python installs are pinned to their real locations **before** `HOME` changes. Without this, the astro helpers' `uv run --with git+https://…stellium` would download again on every run.
- Live hook and service files are not changed. The `ensure-rcs` hook is fixed on the test side only, because the hook runs in every Claude session.

## Requirements

**Global rules (every row)**

- **G1** Each row's done check is its labelled block under "Done checks". It is copied verbatim into the brief.
- **G2** Tests are hermetic (checklist item 4). They run with `uv run lib/python/run_tests.py <component or file>` from the worktree root (item 5), never with `cmds test` or a bare `pytest`.
- **G3** No `rm` (item 9). Use `trash`, `tmp_path`, or a `tempfile.TemporaryDirectory` that removes itself.
- **G4** A behaviour change updates its doc in the same row (item 10).

### R1 Revive test independent of tmux (row REVIVE)

- R1.1 `TestThisPane::test_a_pane_whose_last_shell_only_ran_revive_speaks_for_the_real_ghost` uses the `in_pane` fixture. `in_pane` (`test_revive.py:393`) also removes `TMUX_PANE` and `TERM_SESSION_ID`.
- R1.2 Add a new test, `test_here_under_tmux_finds_the_tmux_pane_ghost`. It sets `TMUX` and `TMUX_PANE` itself, writes a ghost keyed `<G>-<pane>-<epoch>`, and asserts that `revive.cmd_get("here") == 0`. This pins the product's tmux keying.
- R1.3 First confirm the cause: run the file with `TMUX` set, where it should fail, and unset, where it should pass. If it also fails with `TMUX` unset, find the real cause before you change the test.
- Only `tests/` changes. No live path.

### R2 svc pane tests independent of tmux (row SVC-KEYS)

- R2.1 Add a `no_tmux_env()` helper in `tests/svc/test_svc.py`. It returns `os.environ` without `TMUX` and `TMUX_PANE`. Pass it to `panes(...)` in every pane test except `test_q_under_tmux_stops_but_keeps_the_supervisor`, which sets its own fake `TMUX`.
- R2.2 Confirm the cause first, the same way as R1.3. Record the result in the worklog.
- Only `tests/` changes.

### R3 Diagnose the clean-exit svc test (row SVC-EXIT)

- R3.1 Reproduce `test_clean_exit_closes_the_window_crash_keeps_it` five times in each of four cases: `TMUX` set, `TMUX` unset, inside a real tmux pane, and from a plain terminal. Find which assertion fails: line 771, 773, 777 or 780.
- R3.2 Read `bin/svc-tmux`: the `new-window`/`new-session` launch at lines 156 and 171, `--wait` with its `timeout=180` default at line 219, and the respawn of dead panes. Then classify the failure as a real bug, timing, or environment.
- R3.3 Fix the failure according to its class:
  - **Test bug**: `run([SVC, "stop", "web"], proj)` already omits `tmux_env`. Pass `tmux_env` to it, and wait on the dead-window listing rather than read it once.
  - **Product bug**: fix `bin/svc-tmux` or `bin/supervise`, and update `wiki/pages/supervise-svc.md`.
  - **Environment that the test cannot control**: use `skipif` with a written reason. Use this only with a reproduced cause.
- R3.4 Write the finding to `.cc/reports/REPORT-svc-clean-exit.md`.
- **Live path note:** `bin/supervise` and `bin/svc-tmux` run from `~/dotfiles/bin` on `PATH` as soon as they merge. If the fix touches either one, the operator checks it with `svc-tmux up --wait <name>` and `svc stop <name>` in a project that has a `.svc.conf`. The window must close on a clean stop.

### R4 Runner isolation (row ISOLATE)

- R4.1 In `lib/python/run_tests.py`, add a pure function `isolated_env(base: dict, home: Path, uv_cache: str, uv_python: str) -> dict` and a context manager `test_home()`.
  - `test_home()` makes a `tempfile.TemporaryDirectory(prefix="dotfiles-test-home-")`.
  - Inside it, it creates a `dotfiles` symlink to `DOTFILES`, plus `.config/`, `.local/share/`, `.local/state/` and `.cache/`.
  - It writes `.gitconfig` with a test identity (`user.name`, `user.email`) and `init.defaultBranch = master`.
  - It writes `.config/jj/config.toml` with a `[user]` table.
- R4.2 `isolated_env` sets these variables:
  - `HOME`;
  - `XDG_CONFIG_HOME`, `XDG_DATA_HOME`, `XDG_STATE_HOME` and `XDG_CACHE_HOME`, at the standard paths under `HOME`. `ccjj.py` hard-codes `~/.local/state/ai-jj-commit` (lines 283 and 702), so the state folder must sit under `HOME`;
  - `GIT_CONFIG_GLOBAL`, `GIT_CONFIG_NOSYSTEM=1`, `JJ_CONFIG`, `JJ_USER` and `JJ_EMAIL`;
  - `UV_CACHE_DIR` and `UV_PYTHON_INSTALL_DIR`, to the values passed in.

  It removes these variables: `TMUX`, `TMUX_PANE`, `ITERM_SESSION_ID`, `TERM_SESSION_ID`, `CLAUDECODE`, `SVC_FS_CONFIG`, `SVC_TMUX_SOCKET`, and every name that starts with `CLAUDE_`, `CCS_` or `CC_JJ_`. It keeps `PATH` and every other variable.
- R4.3 `run_pytest` computes the uv folders once from the real environment. It reads an existing `UV_CACHE_DIR` or `UV_PYTHON_INSTALL_DIR` first. Otherwise it uses `uv cache dir` and `uv python dir`. It runs each pytest under `test_home()` with `isolated_env`. `stream()` gets an `env` parameter.
- R4.4 A `COMPONENTS` entry may hold `"isolation": False` and an `"isolation_reason"` string. The runner then uses the inherited environment and prints the reason. No component uses this in this row.
- R4.5 Tests in `tests/lib/python/test_run_tests.py`:
  - `test_isolated_env_points_home_and_xdg_into_the_test_home`
  - `test_isolated_env_keeps_the_uv_folders`
  - `test_isolated_env_drops_terminal_and_claude_variables`
  - `test_test_home_links_dotfiles_to_the_tree_under_test`
  - `test_run_pytest_runs_under_the_isolated_env`
- R4.6 Docs:
  - Add an "Isolation" section to `docs/testing.md`: what is set, what is removed, why uv is pinned, the opt-out key, and that `cmds test` gets the same isolation.
  - Add one paragraph to the CLAUDE.md "Testing" section.
- Not a live path: `lib/python/run_tests.py` runs only under `cmds test` and the gate.

### R5 Astro offline (row ASTRO)

- R5.1 `tests/bin/astro/conftest.py` `astro_module` loads `Path(__file__).resolve().parents[3] / "bin" / "astro"`.
- R5.2 `ZRCalculator._birth_payload` in `bin/astro` adds `lat`, `lng` and `tz_str` when the chart has coordinates. A chart has coordinates when `tz_str` is non-empty and `(lat, lng) != (0.0, 0.0)`. `BirthData.lat`, `.lng` and `.tz_str` (lines 73–75) default to `0.0`, `0.0` and `""`, which means "not geocoded".
- R5.3 `_build_chart` in `bin/astro-zr-helper` passes `{"latitude", "longitude", "timezone", "name": city}` when the payload has `lat` and `lng`. Otherwise it passes the city string, as it does today. Update the module docstring's request format (lines 8–19).
- R5.4 New tests in `tests/bin/astro/test_zr.py`:
  - `test_birth_payload_sends_saved_coordinates`
  - `test_birth_payload_without_coordinates_keeps_the_city`
  - `test_timeline_ignores_the_city_when_coordinates_are_given`: the same reference L1 Fortune periods, with `city="Nowhere-Invalid"`. This proves that no geocoder runs.
- R5.5 Do not change the `L1_*`/`L2_*` reference data, `DATE_TOL_DAYS` or any assertion. If a period moves by more than one day, stop and report it.
- R5.6 Docs: in the zodiacal-releasing section of `docs/astro.md`, say that the chart's saved coordinates are used. The city is geocoded only when the chart has none.
- **Live path:** `bin/astro` and `bin/astro-zr-helper` run from `~/dotfiles/bin` on `PATH`. They are not checklist item 2 paths, but they are live on merge. The operator checks that `astro zr` and `astro zr --age 32` print the same periods as before for their saved chart.

### R6 ensure-rcs tests use the tree under test (row HOOKS)

- R6.1 In `tests/hooks/test_ensure_rcs.py`:
  - `run_hook` and `run_hook_raw` always pass a throwaway `HOME`, through a fixture-built home with `dotfiles` linked to `DOTFILES`;
  - the fixture creates the destinations the tests name: `.config/tmux/tmux.conf`, `.config/fish/config.fish`, `.claude/CLAUDE.md`, `.claude/hooks/ensure-rcs.sh` and `Library/LaunchAgents/org.pancia.vpc.plist`;
  - replace every `Path.home()` (lines 34–100, 223 and 239);
  - `TestJsonParsing.DST` becomes fixture-based.
- R6.2 New test: `TestPreMode::test_reads_the_manifest_of_the_tree_under_test`. It picks the first non-comment entry of `DOTFILES/rcs/MANIFEST` and asserts that the entry's destination is blocked.
- R6.3 Make the rest of the `hooks` component pass under R4 isolation.
- Only `tests/` changes. **`rcs/claude-ensure-rcs-hook.sh` is not edited** (live in every Claude session).

### R7 ccjj tests own their home and identity (row CCJJ)

- R7.1 In `tests/lib/python/test_ccjj.py`:
  - an autouse fixture sets `HOME` to `tmp_path / "home"`;
  - `Repo.__init__` and `Repo.run` (lines 36–72) pass `JJ_USER`, `JJ_EMAIL` and a `JJ_CONFIG` file;
  - the lock-folder tests (around lines 1275–1300 and 1956) then resolve under that home.
- R7.2 New test: `test_the_shared_lock_is_under_the_test_home`.
- Only `tests/` changes.

### R8 Fish panes keep the real home out (row FISH)

- R8.1 `FishPane.run` in `tests/fish/conftest.py` (env at line 82) sets `HOME`, `XDG_DATA_HOME` and `XDG_CONFIG_HOME` under the pane's own state folder. Interactive fish writes `$XDG_DATA_HOME/fish/fish_history` even with `--no-config`, so the panes likely write test commands into the operator's history today. Confirm this.
- R8.2 New file `tests/fish/test_pane_isolation.py` with `test_an_interactive_pane_writes_history_only_in_its_own_home`.
- R8.3 Make the whole `fish` component pass under isolation. Each changed `.fish` file passes `fish -n` (item 8). No `.fish` file is expected to change.
- Only `tests/` changes.

### R9 Remaining components under isolation, part A (row REST-A)

- R9.1 `roleplay`:
  - `roleplay/tests/test_roleplay_roll.py:705` (`_roll`) and `roleplay/tests/test_roleplay_say.py` (lines 59 and 120) pass a `tmp_path` home, not `Path.home()`;
  - the module-level `_FAKE_HOME = Path(tempfile.mkdtemp(...))` (`test_roleplay_roll.py:30`) leaks a folder on every run. Replace it with a session fixture from `tmp_path_factory`.
- R9.2 `mods`: run `claude plugin test` under the isolated home. If it fails only because of the fake home, set `"isolation": False` with a reason on `mods`. Its docstring says it "needs no login and writes nothing". Also record the failure in `docs/testing.md`.
- R9.3 `lib/lua`: confirm it passes under isolation. No change is expected, because `harness.lua` takes its own paths.

### R10 Remaining components under isolation, part B (row REST-B)

- R10.1 Run each component under isolation, then fix it or mark it with a reason in `docs/testing.md`: `bin/cc-peers`, `bin/scratch`, `bin/ytdl`, `bin/exocortex-id`, `services/server_check`, `services/youtube_transcribe` and the whole `lib/python`.
- R10.2 The git tests in `cc-peers`, `test_cc_worktree.py` and `test_cc_worktree_nudge.py` no longer run the live `~/dotfiles/git/hooks`. `rcs/gitconfig:6` sets `hooksPath = ~/dotfiles/git/hooks`, and R4's `GIT_CONFIG_GLOBAL` replaces that setting. Confirm that each component passes without those hooks.

### R11 Per-component run time (row TIMING)

- R11.1 `run_all` and `run_many` time each component with `time.monotonic()`. `print_summary` prints each component's wall time on its line, and the total on the last line.
- R11.2 New test in `test_run_tests.py`: `test_summary_shows_each_components_time`.
- R11.3 Docs: add a "Run time" section to `docs/testing.md`. It says how to read the times, and gives the known figures from the Technical Approach. The operator's GATE-RUN step adds the measured times.

### R12 Clean-clone guard (row CANARY)

- R12.1 New file `tests/lib/python/test_hermetic_env.py`:
  - `test_home_is_a_throwaway`: `HOME` differs from `pwd.getpwuid(os.getuid()).pw_dir` and lies under the system temp folder;
  - `test_dotfiles_in_home_is_the_tree_under_test`;
  - `test_no_test_names_the_live_checkout`: scans `tests/**/*.py` and `roleplay/tests/*.py` for `Path.home() / "dotfiles"`, `~/dotfiles` and `$HOME/dotfiles`. A small allowlist covers docstrings, and each entry has a reason.
- R12.2 Docs: in `docs/testing.md`, say that a bare `pytest` fails `test_home_is_a_throwaway` on purpose.

## Acceptance Criteria

- The zodiacal-releasing tests pass without consulting a geocoder, and their reference data is unchanged.
- The astro tests load `bin/astro` from the tree under test.
- The revive "here" test passes when the runner's environment has `TMUX` and `TMUX_PANE` set.
- The supervise key and bar tests pass when the runner's environment has `TMUX` set.
- The clean-exit svc test has a written cause and passes three runs in a row.
- Every component's pytest runs with a throwaway `HOME`, XDG folders, git and jj identity, a pinned uv cache, and no terminal or Claude session variables.
- The ensure-rcs tests read the MANIFEST of the tree under test.
- The ccjj lock folder lands in the test home, not the real one.
- Interactive fish panes write history only in their own home.
- `roleplay`, `mods` and `lib/lua` pass under isolation, or carry a written opt-out reason.
- The remaining Python, bin and service components pass under isolation.
- The run summary shows each component's wall time.
- No test names the live `~/dotfiles` checkout.
- The full suite passes from a fresh clone outside `~/dotfiles`, both inside and outside tmux.
- The operator decides whether the gate needs a faster target, based on the measured times.

```acceptance
{"v":1,"criteria":[
 {"id":"AC1","text":"The zodiacal-releasing tests pass without consulting a geocoder, with the reference data unchanged.","checks":[{"row":"ASTRO","check":"astro component"}]},
 {"id":"AC2","text":"The astro tests load bin/astro from the tree under test.","checks":[{"row":"ASTRO","check":"astro component"}]},
 {"id":"AC3","text":"The revive here test passes with TMUX and TMUX_PANE set in the runner's environment.","checks":[{"row":"REVIVE","check":"revive under tmux"}]},
 {"id":"AC4","text":"The supervise key and bar tests pass with TMUX set in the runner's environment.","checks":[{"row":"SVC-KEYS","check":"svc pane tests under tmux"}]},
 {"id":"AC5","text":"The clean-exit svc test has a written cause and passes three runs in a row.","checks":[{"row":"SVC-EXIT","check":"clean exit three runs"},{"row":"SVC-EXIT","check":"finding written"}]},
 {"id":"AC6","text":"Every component's pytest runs with a throwaway HOME, XDG folders, git and jj identity, a pinned uv cache and no terminal or Claude variables.","checks":[{"row":"ISOLATE","check":"isolation unit tests"}]},
 {"id":"AC7","text":"The ensure-rcs tests read the MANIFEST of the tree under test.","checks":[{"row":"HOOKS","check":"hooks component"}]},
 {"id":"AC8","text":"The ccjj lock folder lands in the test home, not the real one.","checks":[{"row":"CCJJ","check":"ccjj file"}]},
 {"id":"AC9","text":"Interactive fish panes write history only in their own home.","checks":[{"row":"FISH","check":"fish component"}]},
 {"id":"AC10","text":"roleplay, mods and lib/lua pass under isolation or carry a written opt-out reason.","checks":[{"row":"REST-A","check":"roleplay component"},{"row":"REST-A","check":"mods component"},{"row":"REST-A","check":"lua component"}]},
 {"id":"AC11","text":"The remaining Python, bin and service components pass under isolation.","checks":[{"row":"REST-B","check":"lib/python component"},{"row":"REST-B","check":"cc-peers component"},{"row":"REST-B","check":"scratch component"},{"row":"REST-B","check":"ytdl component"},{"row":"REST-B","check":"exocortex component"},{"row":"REST-B","check":"server-check component"},{"row":"REST-B","check":"youtube component"}]},
 {"id":"AC12","text":"The run summary shows each component's wall time.","checks":[{"row":"TIMING","check":"summary test"},{"row":"TIMING","check":"recorded two-component run"}]},
 {"id":"AC13","text":"No test names the live ~/dotfiles checkout.","checks":[{"row":"CANARY","check":"hermetic guard"}]},
 {"id":"AC14","text":"The full suite passes from a fresh clone outside ~/dotfiles, inside and outside tmux.","human":"Operator runs the gate command from a fresh clone in both settings (GATE-RUN) and confirms PASSED in the summary."},
 {"id":"AC15","text":"The operator decides whether the gate needs a faster target, from the measured times.","human":"Read the per-component times from GATE-RUN and answer the first Open Question."}
]}
```

## Documentation Updates

- `docs/testing.md`:
  - "Isolation" section (ISOLATE);
  - opt-out reasons for any component (REST-A, REST-B);
  - "Run time" section with the known figures (TIMING);
  - the bare-pytest canary (CANARY).
- `CLAUDE.md`, "Testing" section: one paragraph saying that every run gets a throwaway home with `dotfiles` linked to the tree under test, and that tests must not rely on the real home (ISOLATE).
- `docs/astro.md`, "Zodiacal Releasing (`zr`)": coordinates come from the saved chart, and the city is geocoded only as a fallback (ASTRO).
- `wiki/pages/supervise-svc.md`: only if SVC-EXIT changes `bin/svc-tmux` or `bin/supervise`.
- `ai/skills/`: none.

## Technical Approach

**Order.** The two tmux-only test fixes, REVIVE and SVC-KEYS, land first. Their done checks set `TMUX` in the command, so each check fails before its fix whatever the gate's environment is. After ISOLATE merges, the runner removes `TMUX`, and those checks still pass. ISOLATE comes next. Each later row then makes its own component pass under isolation, and each row's check runs only that component. CANARY comes last, because its static scan fails until HOOKS, ASTRO and REST-A remove the live-checkout paths.

**Audit results (requirement 4).** The test files are the same on `master` and the checked-out commit. Verdicts by component:

| Component | Finding | Severity | Row |
|---|---|---|---|
| `bin/astro` | `conftest.py:29` loads `~/dotfiles/bin/astro`. The zodiacal-releasing helper geocodes over the network. The helper shebang installs stellium from an unpinned git URL | Fails outside `~/dotfiles`; needs network | ASTRO |
| `hooks` | `test_ensure_rcs.py`: `TestPreMode`, `TestJsonParsing` and `TestPerformance` run the hook with the real `HOME`, so they read the live `~/dotfiles/rcs/MANIFEST`. The other hook tests inherit `HOME` but set their own state folders | Reads real state; tests the wrong tree | HOOKS |
| `lib/python` | `test_ccjj.py` creates and deletes `~/.local/state/ai-jj-commit/<repo>.lock` in the real home. Its jj runs use the real jj config and identity. `test_revive.py` leaks `TMUX` (cause 2). `test_cc_worktree.py` sets its identity but inherits the global `hooksPath` | Writes real state | CCJJ, REVIVE, REST-B |
| `fish` | The `FishPane` pty shells (`conftest.py:82`) inherit `HOME` and `XDG_DATA_HOME`, so they likely append to the real fish history. They already drop `TMUX`. `test_jump_commands.py` copies `os.environ`, but its stubs cover writes | Writes real state (likely) | FISH |
| `svc` | `private_fs_config` isolates the vault, and tmux uses private sockets. Pane tests leak `TMUX` (cause 3). `tmux_env` reads the tree's own `lib/svc/tmux.conf` | Fails inside tmux | SVC-KEYS, SVC-EXIT |
| `roleplay` | `_roll` and `test_roleplay_say.py` pass the real `HOME` to the scripts. `mkdtemp` leaks a folder on each run | Reads real state | REST-A |
| `mods` | `claude plugin test` runs with the real `HOME`. It skips cleanly when `claude` is missing | Reads real state | REST-A |
| `bin/cc-peers`, `hooks/test_cc_worktree_nudge.py` | Temp git repos with an identity in the repo, but `git commit` runs the live `~/dotfiles/git/hooks` through `rcs/gitconfig:6` | Runs live-checkout code | REST-B |
| `bin/scratch` | Sets its own `HOME`, `SCRATCH_ROOT`, git and jj identity, and `JJ_CONFIG=/dev/null` | Clean | — |
| `services/server_check` | Fakes the server state and runs dry. Checked: `script.sh` reads `$HOME/.ssh` only when the server state is not faked | Clean | — |
| `lib/lua` | `harness.lua` gets every path from the test. Skips cleanly without `lua5.4` | Clean | — |
| `bin/ytdl`, `bin/exocortex-id`, `services/youtube_transcribe` | Not inspected in depth. `ytdl` sets `HOME` in 3 places | Unknown | REST-B |

**Clean clone (requirement 5).** Every done check runs in a scratch clone outside `~/dotfiles`, so each row proves this for its own component. Before this work, a clone passed only because the live `~/dotfiles` happened to exist. `test_dotfiles_in_home_is_the_tree_under_test` and the static scan keep it that way.

**Run time (requirement 6).** Known facts:
- The full run took about 14 minutes (operator's figure).
- `fish` takes about 3 minutes, because each pty test waits 2.6 s (`SETTLE` in `tests/fish/conftest.py`).

Test functions per component, counted from the source (parametrize adds more):

| Component | Tests | Main cost |
|---|---|---|
| lib/python | 445 | 214 of them are ccjj tests that call jj |
| fish | 166 | pty tests |
| youtube_transcribe | 127 | |
| astro | 107 | uv helper subprocesses; slower once the zodiacal-releasing tests really run |
| hooks | 103 | |
| roleplay | 99 | |
| ytdl | 46 | |
| scratch | 38 | |
| exocortex-id | 37 | |
| svc | 33 | a tmux server per test, waits up to 15–30 s |
| lib/lua | 15 | |
| cc-peers | 14 | |
| server_check | 10 | |
| mods | 2 | `claude plugin test` each, 300 s timeout |

No per-component seconds were measured, and this spec gives none. TIMING makes every run print them, and GATE-RUN records the first clean set. Recommendation: keep the full suite as the gate in observe mode. The decision is the first Open Question.

**Residual risks**

- `uv` under a fake `HOME` loses `~/.config/uv/uv.toml`. If that file sets an index or `exclude-newer` that the suite needs, ISOLATE must pass `UV_CONFIG_FILE`.
- `claude plugin test` may not start under a fake home. REST-A then uses the opt-out with its reason.
- The stellium helper installs from an unpinned git HEAD. A first run on a fresh machine needs network. An upstream change can also move the reference dates.
- Coordinates instead of the geocoded city could move a period by more than one day. R5.5 says to stop and report rather than widen the tolerance.
- SVC-EXIT may find a product bug in `bin/svc-tmux`. That is live on merge (R3).

**Cost estimate.** 12 missions, from 15 to 40 minutes each, about 6.5 worker-hours in total. That is roughly **26 5h points** and **8 7d points**, assuming about 4 5h points per worker-hour and about 1 7d point per 1.5 mission. Treat these as estimates.

### Mission Breakdown

| Order | Row | Mission | Scope | Est. | Deps | Pri |
|---|---|---|---|---|---|---|
| 1 | REVIVE | Revive "here" test clears tmux variables; add tmux-keyed test | `tests/lib/python/test_revive.py` | 15m | – | P1 |
| 2 | SVC-KEYS | supervise pane tests run without the outer `TMUX` | `tests/svc/test_svc.py` | 25m | – | P1 |
| 3 | SVC-EXIT | Diagnose and fix the clean-exit svc test; write a report | `tests/svc/test_svc.py`, maybe `bin/svc-tmux`, `.cc/reports/` | 40m | SVC-KEYS | P1 |
| 4 | ISOLATE | Runner gives each component a throwaway home and identity, and pins uv | `lib/python/run_tests.py`, `test_run_tests.py`, `docs/testing.md`, `CLAUDE.md` | 40m | – | P1 |
| 5 | ASTRO | Zodiacal-releasing helper uses saved coordinates; conftest loads the tree under test | `bin/astro`, `bin/astro-zr-helper`, `tests/bin/astro/`, `docs/astro.md` | 35m | ISOLATE | P1 |
| 6 | HOOKS | ensure-rcs tests run against a throwaway home linked to the tree | `tests/hooks/` | 35m | ISOLATE | P1 |
| 7 | CCJJ | ccjj tests own their home, lock folder and jj identity | `tests/lib/python/test_ccjj.py` | 25m | ISOLATE | P2 |
| 8 | FISH | Fish panes get their own home; fish component passes under isolation | `tests/fish/` | 35m | ISOLATE | P2 |
| 9 | REST-A | roleplay, mods and lua pass under isolation | `roleplay/tests/`, `lib/python/run_tests.py` (opt-out only), `docs/testing.md` | 35m | ISOLATE | P2 |
| 10 | REST-B | Remaining bin, service and lib/python components pass under isolation | `tests/bin/`, `tests/services/`, `tests/lib/python/`, `docs/testing.md` | 40m | CCJJ | P2 |
| 11 | TIMING | Summary prints per-component wall time | `lib/python/run_tests.py`, `test_run_tests.py`, `docs/testing.md` | 25m | ISOLATE | P2 |
| 12 | CANARY | Guard tests: throwaway home, linked tree, no live-checkout paths | `tests/lib/python/test_hermetic_env.py`, `docs/testing.md` | 25m | ASTRO, HOOKS, REST-A, REST-B | P2 |
| 13 | GATE-RUN | Operator step: run the gate command from a fresh clone outside `~/dotfiles`, once in tmux and once outside. Confirm PASSED, and copy the per-component times into `docs/testing.md` | — | 30m | CANARY, TIMING, SVC-EXIT, FISH | P2 |

### Done checks

- **REVIVE**
```donecheck
{"v":1,"timeout":"5m","checks":[
 {"kind":"command","title":"revive under tmux","run":"TMUX=/tmp/outer-fake,1,0 TMUX_PANE=%99 uv run lib/python/run_tests.py lib/python/test_revive.py -v","stdout_contains":["test_a_pane_whose_last_shell_only_ran_revive_speaks_for_the_real_ghost PASSED","test_here_under_tmux_finds_the_tmux_pane_ghost PASSED"]}
]}
```

- **SVC-KEYS**
```donecheck
{"v":1,"timeout":"8m","checks":[
 {"kind":"command","title":"svc pane tests under tmux","run":"TMUX=/tmp/outer-fake,1,0 TMUX_PANE=%99 uv run lib/python/run_tests.py svc/test_svc.py -v -k \"keys_restart or bar_separator or q_under_tmux\"","stdout_contains":["test_keys_restart_suspend_resume_quit PASSED","test_bar_separator_and_panel_render PASSED","test_q_under_tmux_stops_but_keeps_the_supervisor PASSED"]}
]}
```

- **SVC-EXIT**
```donecheck
{"v":1,"timeout":"10m","checks":[
 {"kind":"command","title":"clean exit three runs","run":"for i in 1 2 3; do uv run lib/python/run_tests.py svc/test_svc.py -v -k clean_exit_closes || exit 1; done","stdout_matches":"(?s)test_clean_exit_closes_the_window_crash_keeps_it PASSED.*test_clean_exit_closes_the_window_crash_keeps_it PASSED.*test_clean_exit_closes_the_window_crash_keeps_it PASSED"},
 {"kind":"command","title":"finding written","run":"grep -E -c 'real bug|timing|environment' .cc/reports/REPORT-svc-clean-exit.md","stdout_matches":"[1-9]"}
]}
```

- **ISOLATE**
```donecheck
{"v":1,"timeout":"5m","checks":[
 {"kind":"command","title":"isolation unit tests","run":"uv run lib/python/run_tests.py lib/python/test_run_tests.py -v","stdout_contains":["test_isolated_env_points_home_and_xdg_into_the_test_home PASSED","test_isolated_env_keeps_the_uv_folders PASSED","test_isolated_env_drops_terminal_and_claude_variables PASSED","test_test_home_links_dotfiles_to_the_tree_under_test PASSED","test_run_pytest_runs_under_the_isolated_env PASSED"]}
]}
```

- **ASTRO**
```donecheck
{"v":1,"timeout":"20m","checks":[
 {"kind":"command","title":"astro component","run":"uv run lib/python/run_tests.py astro -v","stdout_contains":["test_birth_payload_sends_saved_coordinates PASSED","test_birth_payload_without_coordinates_keeps_the_city PASSED","test_timeline_ignores_the_city_when_coordinates_are_given PASSED"],"stdout_matches":"\\b[1-9]\\d{2,} passed"}
]}
```

- **HOOKS**
```donecheck
{"v":1,"timeout":"8m","checks":[
 {"kind":"command","title":"hooks component","run":"uv run lib/python/run_tests.py hooks -v","stdout_contains":["test_reads_the_manifest_of_the_tree_under_test PASSED"],"stdout_matches":"\\b[1-9]\\d+ passed"}
]}
```

- **CCJJ**
```donecheck
{"v":1,"timeout":"10m","checks":[
 {"kind":"command","title":"ccjj file","run":"uv run lib/python/run_tests.py lib/python/test_ccjj.py -v","stdout_contains":["test_the_shared_lock_is_under_the_test_home PASSED"],"stdout_matches":"\\b[1-9]\\d{2,} passed"}
]}
```

- **FISH**
```donecheck
{"v":1,"timeout":"15m","checks":[
 {"kind":"command","title":"fish component","run":"uv run lib/python/run_tests.py fish -v","stdout_contains":["test_an_interactive_pane_writes_history_only_in_its_own_home PASSED"],"stdout_matches":"\\b[1-9]\\d{2,} passed"}
]}
```

- **REST-A**
```donecheck
{"v":1,"timeout":"15m","checks":[
 {"kind":"command","title":"roleplay component","run":"uv run lib/python/run_tests.py roleplay","stdout_matches":"\\b[1-9]\\d+ passed"},
 {"kind":"command","title":"mods component","run":"uv run lib/python/run_tests.py mods -v","stdout_matches":"test_mod_suite_passes\\[[^\\]]+\\] PASSED"},
 {"kind":"command","title":"lua component","run":"uv run lib/python/run_tests.py lib/lua","stdout_matches":"\\b1\\d passed"}
]}
```

- **REST-B**
```donecheck
{"v":1,"timeout":"20m","checks":[
 {"kind":"command","title":"lib/python component","run":"uv run lib/python/run_tests.py lib/python","stdout_matches":"\\b[1-9]\\d{2,} passed"},
 {"kind":"command","title":"cc-peers component","run":"uv run lib/python/run_tests.py bin/cc-peers","stdout_matches":"\\b[1-9]\\d* passed"},
 {"kind":"command","title":"scratch component","run":"uv run lib/python/run_tests.py bin/scratch","stdout_matches":"\\b[1-9]\\d* passed"},
 {"kind":"command","title":"ytdl component","run":"uv run lib/python/run_tests.py bin/ytdl","stdout_matches":"\\b[1-9]\\d* passed"},
 {"kind":"command","title":"exocortex component","run":"uv run lib/python/run_tests.py bin/exocortex-id","stdout_matches":"\\b[1-9]\\d* passed"},
 {"kind":"command","title":"server-check component","run":"uv run lib/python/run_tests.py services/server_check","stdout_matches":"\\b[1-9]\\d* passed"},
 {"kind":"command","title":"youtube component","run":"uv run lib/python/run_tests.py yt","stdout_matches":"\\b[1-9]\\d+ passed"}
]}
```

- **TIMING**
```donecheck
{"v":1,"timeout":"5m","checks":[
 {"kind":"command","title":"summary test","run":"uv run lib/python/run_tests.py lib/python/test_run_tests.py -v","stdout_contains":["test_summary_shows_each_components_time PASSED"]},
 {"kind":"command","title":"recorded two-component run","record":true,"run":"uv run lib/python/run_tests.py bin/exocortex-id services/server_check","stdout_matches":"PASS\\s+bin/exocortex-id.*\\d+(\\.\\d+)?\\s*s"}
]}
```

- **CANARY**
```donecheck
{"v":1,"timeout":"5m","checks":[
 {"kind":"command","title":"hermetic guard","run":"uv run lib/python/run_tests.py lib/python/test_hermetic_env.py -v","stdout_contains":["test_home_is_a_throwaway PASSED","test_dotfiles_in_home_is_the_tree_under_test PASSED","test_no_test_names_the_live_checkout PASSED"]}
]}
```

The TIMING recorded run names two small components, because the summary prints only when more than one component runs. It is not a whole-suite run.

## Out of Scope

- Turning the merge gate on, in observe or enforce mode. This is an operator step after these rows merge.
- Changing `rcs/claude-ensure-rcs-hook.sh`, `lib/python/ccjj.py`'s lock location, or any other live hook or service.
- A faster gate target, such as running components in parallel or a reduced set. This waits for the decision in the first Open Question.
- Pinning stellium in `bin/astro-zr-helper` (second Open Question).
- Porting kerykeion v5 deprecations, or other test warnings.

## Open Questions

1. **Does the gate need a faster target?** Recommendation: not now. Observe mode blocks nothing, so 14 minutes costs only wall time. After GATE-RUN gives measured times, do the following if an enforced gate is over about 10 minutes: add `--jobs N` to `run_tests.py` so that components run in parallel. Each component is already its own process, and svc and fish use unique markers and private sockets. Wall time would then fall to roughly the slowest component, about 3 minutes for fish. A reduced "fast" set would let regressions in the skipped components through.
2. **Pin stellium?** The helper's shebang installs `git+https://github.com/katelouie/stellium` at HEAD. Recommendation: in a follow-up, pin it to the commit the operator's cache resolves today, with `@<sha>`. Then a gate on a fresh machine is repeatable and an upstream change cannot move the reference dates. This changes the live `astro zr`, so the operator approves it.
3. **What if `claude plugin test` needs the real home?** Recommendation: use the R4.4 opt-out for `mods` only, with the reason printed. Do not weaken isolation for any other component.
4. **Remove `TMUX` in the runner as well as in the tests?** Recommendation: yes, do both. The runner removes it so the gate's own tmux pane cannot leak in. The REVIVE and SVC-KEYS fixes keep the tests correct under any runner. Their done checks prove this by setting `TMUX` in the command.
