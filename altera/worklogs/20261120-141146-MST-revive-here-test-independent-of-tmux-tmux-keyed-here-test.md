# Worklog: Revive here test independent of tmux; tmux-keyed here test

**Date**: 20261120-141146-MST
**Task**: m-013
**Agent**: w-19

## Summary

Row REVIVE (R1) of the hermetic-test-suite spec. Only `tests/lib/python/test_revive.py` changed.

- R1.3, confirm first, on the base commit 4b942f05 before any change:
  - `TMUX=/tmp/outer-fake,1,0 TMUX_PANE=%99 uv run lib/python/run_tests.py lib/python/test_revive.py`:
    **1 failed, 60 passed**. The failure was
    `TestThisPane::test_a_pane_whose_last_shell_only_ran_revive_speaks_for_the_real_ghost`,
    `assert 1 == 0` at `test_revive.py:409` (`revive.cmd_get("here")`).
  - `env -u TMUX -u TMUX_PANE uv run lib/python/run_tests.py lib/python/test_revive.py`:
    **61 passed**.
  - So the cause in the spec is right: the outer `TMUX`/`TMUX_PANE` leaked in, and
    `this_pane_key()` added `-99`, so no ghost matched.
- R1.1: the test now uses the `in_pane` fixture (which sets `ITERM_SESSION_ID` and removes
  `TMUX`) instead of `store` plus its own `setenv`. `in_pane` is unchanged.
- R1.2: new `TestThisPane::test_here_under_tmux_finds_the_tmux_pane_ghost`. It sets
  `ITERM_SESSION_ID`, `TMUX` and `TMUX_PANE=%7` with monkeypatch, writes both a bare
  `<G>-100.rec` ghost and a tmux `<G>-7-100.rec` ghost, and asserts that `cmd_get("here") == 0`
  and that the printed cwd and command are the tmux ghost's. Having the bare ghost there too
  means the test fails if the tmux suffix is ever dropped, not only if nothing matches.
- After the change: 62 passed with the fake outer `TMUX` set and 62 passed with it unset. Both
  target tests are PASSED in `-v` output, which is what the done check looks for.

## How It Went

Simple. The brief's cause was correct on the first run, and the fix was a fixture swap plus
one new test.

## System Learnings

- `revive.this_pane_key()` prefers `ITERM_SESSION_ID` over `TERM_SESSION_ID`, so a test that
  sets `ITERM_SESSION_ID` does not need to clear `TERM_SESSION_ID`.
- `in_pane` removes `TMUX` but not `TMUX_PANE`. That is enough, because the suffix needs both.

## Process Improvements

None needed. The brief gave line numbers and exact commands, which made this a few minutes' work.

## Self-Improvement Notes

For a two-line test change, doing the edit directly was quicker than handing it to a subagent.
