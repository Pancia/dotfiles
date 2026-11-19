# Mission: supervise pane tests run without the outer TMUX

**Date**: 20261119-142514-MST
**Task**: m-014 bold-lake

## Objective
Implement row SVC-KEYS (requirement R2) of the spec `altera/specs/20261119-121426-MST-green-hermetic-test-suite-for-the-merge-gate.md`. The spec's requirements and its global rules G1 to G4 are authoritative; read it with `git show master:<path>`. Altera inserts the row's done-check block.

## Done Check

```donecheck
{"v":1,"timeout":"8m","checks":[
 {"kind":"command","title":"svc pane tests under tmux","run":"TMUX=/tmp/outer-fake,1,0 TMUX_PANE=%99 uv run lib/python/run_tests.py svc/test_svc.py -v -k \"keys_restart or bar_separator or q_under_tmux\"","stdout_contains":["test_keys_restart_suspend_resume_quit PASSED","test_bar_separator_and_panel_render PASSED","test_q_under_tmux_stops_but_keeps_the_supervisor PASSED"]}
]}
```

## Context
- `bin/supervise` line 268 sets `in_tmux=1` when `TMUX` is set. Then the `q` key stops the service but keeps the supervisor running.
- `tests/svc/test_svc.py`:
  - the `panes()` fixture is at line 190;
  - `test_keys_restart_suspend_resume_quit` (line 204) and `test_bar_separator_and_panel_render` (line 236) start `supervise` with the inherited environment, then expect `q` to exit 0 (lines 215 and 253). Inside tmux they hang, then fail;
  - `test_q_under_tmux_stops_but_keeps_the_supervisor` (line 220) sets its own fake `TMUX` and must keep doing so.
- Steps:
  1. R2.2: confirm the cause first, as in R1.3. Run the pane tests with `TMUX` set and unset, and record both results in the worklog.
  2. R2.1: add a `no_tmux_env()` helper. It returns `os.environ` without `TMUX` and `TMUX_PANE`. Pass it to `panes(...)` in every pane test except `test_q_under_tmux_stops_but_keeps_the_supervisor`.
- After ISOLATE merges, the runner strips `TMUX`. The helper keeps the tests correct under any runner, so do not depend on the runner.

## Constraints
- You work in a git worktree. Use `git`; `jj`, `g`, `commit-mine` and `ccjj` are denied. Never push.
- Run tests with `uv run lib/python/run_tests.py <component or file>` from the worktree root, never `cmds test` (it tests ~/dotfiles, not your tree).
- Tests are hermetic: no test touches the real HOME, ~/.config, ~/Library/LaunchAgents, ~/.claude, a live tmux server or a running service.
- Never use `rm`; use `trash`. Never write a secret or private detail into a tracked file: the repository is public.
- Only `tests/svc/test_svc.py` changes. No live path is touched.

## Success Criteria
- The key and bar tests pass with `TMUX` and `TMUX_PANE` set in the runner's environment.
- `test_q_under_tmux_stops_but_keeps_the_supervisor` still passes.
- The worklog records the result of the confirm-first runs.
- Every check in the done check passes.
- No doc changes: this is a test-only fix.

## Out of Scope
- `test_clean_exit_closes_the_window_crash_keeps_it` (SVC-EXIT). It edits the same file after this mission merges.
- Any change to `bin/supervise`, `bin/svc` or `bin/svc-tmux`.
- Runner isolation (ISOLATE).
