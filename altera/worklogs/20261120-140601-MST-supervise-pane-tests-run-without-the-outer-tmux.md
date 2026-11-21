# Worklog: supervise pane tests run without the outer TMUX

**Date**: 20261120-140601-MST
**Task**: m-014
**Agent**: w-16

## Summary

Row SVC-KEYS (R2). Added `no_tmux_env()` to `tests/svc/test_svc.py`. It returns
`os.environ` without `TMUX` and `TMUX_PANE`. Every `panes(...)` call now passes it:
`test_keys_restart_suspend_resume_quit`, `test_bar_separator_and_panel_render`,
`test_tty_mode_restored_after_ctrl_c` and `test_closing_the_terminal_stops_and_drains`.
`test_q_under_tmux_stops_but_keeps_the_supervisor` keeps its own fake `TMUX`.
Only that test file changed.

### R2.2 confirm-first runs (before the change)

Selection: `-k "keys_restart or bar_separator or q_under_tmux or tty_mode or closing_the_terminal"`.

- `TMUX=/tmp/outer-fake,1,0 TMUX_PANE=%99`: **2 failed, 3 passed**.
  `test_keys_restart_suspend_resume_quit` and `test_bar_separator_and_panel_render`
  failed at `assert p.wait_exit() == 0` with `assert None == 0`. Every step before
  `q` passed, so `q` kept the supervisor alive, which is the `in_tmux=1` path in
  `bin/supervise`. The other three passed.
- `TMUX` and `TMUX_PANE` unset: **5 passed**.

The cause is confirmed: the inherited `TMUX`, and nothing else.

### After the change

- `TMUX` set, same selection: 5 passed. `TMUX` unset: 5 passed.
- Whole `svc/test_svc.py` with `TMUX` and `TMUX_PANE` set: 35 passed (75 s).

## How It Went

Small and direct. The confirm-first runs matched the brief's diagnosis exactly.
I also applied the helper to the tty-mode and closing-the-terminal tests. They pass
under tmux today, but R2.1 says "every pane test except" the q-under-tmux one.

## System Learnings

- `Pane` passes `env` straight to `execvpe`, so a filtered dict is all that is needed.
  No fixture change.
- The `q` under tmux path keeps the supervisor and does not fail fast. Under tmux the
  tests fail only after the `wait_exit` timeout, not with a clear error.

## Process Improvements

The brief's line numbers were exact, and its done check covered the same tests, so
no exploration was needed. Rows with a confirm-first step could give the exact `-k`
selection to run with and without `TMUX`. Then each worker's evidence is the same.

## Self-Improvement Notes

Running the selection with and without `TMUX` in one command gave the R2.2 evidence
and the baseline together.
