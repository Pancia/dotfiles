# Mission: Diagnose and fix the clean-exit svc test; write the report

**Date**: 20261119-142514-MST
**Task**: m-015 bold-lark

## Objective
Implement row SVC-EXIT (requirement R3) of the spec `altera/specs/20261119-121426-MST-green-hermetic-test-suite-for-the-merge-gate.md`. The spec's requirements and its global rules G1 to G4 are authoritative; read it with `git show master:<path>`. Altera inserts the row's done-check block. The job is to diagnose first, then fix according to the class you find.

## Done Check

```donecheck
{"v":1,"timeout":"10m","checks":[
 {"kind":"command","title":"clean exit three runs","run":"for i in 1 2 3; do uv run lib/python/run_tests.py svc/test_svc.py -v -k clean_exit_closes || exit 1; done","stdout_matches":"(?s)test_clean_exit_closes_the_window_crash_keeps_it PASSED.*test_clean_exit_closes_the_window_crash_keeps_it PASSED.*test_clean_exit_closes_the_window_crash_keeps_it PASSED"},
 {"kind":"command","title":"finding written","run":"head -1 .cc/reports/REPORT-svc-clean-exit.md","stdout_matches":"^Class: (test bug|product bug|timing|environment|not reproduced)$"}
]}
```

## Context
- `tests/svc/test_svc.py`:
  - `test_clean_exit_closes_the_window_crash_keeps_it` (line 770);
  - its `tmux_env` fixture (line 556) already drops `TMUX`;
  - the assertions are at line 771 (`svc-tmux up --wait web`), line 773 (the web window is gone after the stop), line 777 (the dead-window listing shows `broken 1`) and line 780 (the crash screen text);
  - the `svc stop web` call at line 772 passes no `tmux_env`.
- `bin/svc`: `cmd_stop` (line 212) sends TERM.
- `bin/supervise`: TERM goes to `on_stop` (the traps at lines 223 to 230), and it exits 0.
- `lib/svc/tmux.conf` line 18: `remain-on-exit failed` should then close the window.
- `bin/svc-tmux`:
  - `new-window` launch at line 156 and `new-session` launch at line 171;
  - `--wait` with its `timeout=180` default at line 219;
  - the respawn of dead panes.
- SVC-KEYS has merged. Reuse its `no_tmux_env()` helper if it fits.
- Steps:
  1. R3.1: reproduce the test five times in each of three setups: `TMUX` set in the command; `TMUX` unset; and from inside a pane of a private tmux server (`tmux -L <unique> new-session -d ...`). Note which assertion fails.
  2. R3.2: read `bin/svc-tmux`. Classify the failure with exactly one of: `test bug`, `product bug`, `timing`, `environment`, `not reproduced`.
  3. R3.3: fix according to the class. The spec lists the fix for each class:
     - test bug: pass `tmux_env` to the stop call, and wait on the dead-window listing rather than read it once;
     - product bug: fix `bin/svc-tmux` or `bin/supervise`, and update `wiki/pages/supervise-svc.md`;
     - timing: a bounded wait on the condition, never a fixed sleep;
     - environment: `skipif` with a written reason, only with a reproduced cause;
     - not reproduced: no product change. Record all fifteen runs, and still apply the `tmux_env` fix.
  4. R3.4: write `.cc/reports/REPORT-svc-clean-exit.md`. Its first line is exactly `Class: <word>`.
- In the report, describe the original failure's environment (inside the operator's tmux) in general terms only: no home paths, user names or host names.

## Constraints
- You work in a git worktree. Use `git`; `jj`, `g`, `commit-mine` and `ccjj` are denied. Never push.
- Run tests with `uv run lib/python/run_tests.py <component or file>` from the worktree root, never `cmds test` (it tests ~/dotfiles, not your tree).
- Tests are hermetic: no test touches the real HOME, ~/.config, ~/Library/LaunchAgents, ~/.claude, a live tmux server or a running service. Use only private tmux sockets (`tmux -L <unique>`) and stop every server you start.
- Never use `rm`; use `trash`. Never write a secret or private detail into a tracked file: the repository is public.
- Live path: `bin/supervise` and `bin/svc-tmux` run from `~/dotfiles/bin` on `PATH` as soon as they merge. If your fix touches either one, say so in the mission-ready note. The operator then checks it with `svc-tmux up --wait <name>` and `svc stop <name>` in a project that has a `.svc.conf`. The window must close on a clean stop.

## Success Criteria
- `test_clean_exit_closes_the_window_crash_keeps_it` passes three runs in a row.
- `.cc/reports/REPORT-svc-clean-exit.md` starts with `Class: <word>`, using one of the five words. It records the fifteen reproduction runs and the assertion that failed.
- The stop call passes `tmux_env`.
- If `bin/svc-tmux` or `bin/supervise` changed, `wiki/pages/supervise-svc.md` is updated.
- Every check in the done check passes.

## Out of Scope
- The pane key and bar tests (SVC-KEYS, merged before this).
- Runner isolation (ISOLATE, which waits for this mission).
