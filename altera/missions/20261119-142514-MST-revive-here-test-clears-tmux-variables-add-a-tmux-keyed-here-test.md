# Mission: Revive here test clears tmux variables; add a tmux-keyed here test

**Date**: 20261119-142514-MST
**Task**: m-013 bold-jade

## Objective
Implement row REVIVE (requirement R1) of the spec `altera/specs/20261119-121426-MST-green-hermetic-test-suite-for-the-merge-gate.md`. The spec's requirements and its global rules G1 to G4 are authoritative; read it with `git show master:<path>`. Altera inserts the row's done-check block.

## Done Check

```donecheck
{"v":1,"timeout":"5m","checks":[
 {"kind":"command","title":"revive under tmux","run":"TMUX=/tmp/outer-fake,1,0 TMUX_PANE=%99 uv run lib/python/run_tests.py lib/python/test_revive.py -v","stdout_contains":["test_a_pane_whose_last_shell_only_ran_revive_speaks_for_the_real_ghost PASSED","test_here_under_tmux_finds_the_tmux_pane_ghost PASSED"]}
]}
```

## Context
- `tests/lib/python/test_revive.py`: `TestThisPane::test_a_pane_whose_last_shell_only_ran_revive_speaks_for_the_real_ghost` (line 400) uses the `store` fixture (line 30), so an outer `TMUX` leaks into it. The `in_pane` fixture (line 393) sets `ITERM_SESSION_ID` and removes `TMUX`.
- `lib/python/revive.py`: `this_pane_key()` (line 239) appends `-<TMUX_PANE>` only when both `TMUX` and `TMUX_PANE` are set. Without `ITERM_SESSION_ID` it returns an empty string. Under tmux no ghost matches, so `cmd_get('here')` returns 1.
- The done check sets a fake `TMUX` and `TMUX_PANE` in its command. Today the runner passes them through. After ISOLATE merges, the runner strips them, so the new test must set its own variables and must not rely on the runner.
- Steps:
  1. R1.3: first confirm the cause. Run the file with `TMUX` set, where it should fail, and with it unset, where it should pass. Record both results in the worklog. If it also fails with `TMUX` unset, find the real cause before you change the test.
  2. R1.1: switch the test to the `in_pane` fixture. Do not change `in_pane` itself.
  3. R1.2: add `test_here_under_tmux_finds_the_tmux_pane_ghost`. It sets `ITERM_SESSION_ID`, `TMUX` and `TMUX_PANE` with monkeypatch, writes a ghost keyed `<G>-<pane>-<epoch>`, and asserts that `revive.cmd_get('here') == 0`. This pins the product's tmux keying.

## Constraints
- You work in a git worktree. Use `git`; `jj`, `g`, `commit-mine` and `ccjj` are denied. Never push.
- Run tests with `uv run lib/python/run_tests.py <component or file>` from the worktree root, never `cmds test` (it tests ~/dotfiles, not your tree).
- Tests are hermetic: no test touches the real HOME, ~/.config, ~/Library/LaunchAgents, ~/.claude, a live tmux server or a running service.
- Never use `rm`; use `trash`. Never write a secret or private detail into a tracked file: the repository is public.
- Only `tests/lib/python/test_revive.py` changes. No live path is touched.

## Success Criteria
- The existing here test passes with `TMUX` and `TMUX_PANE` set in the runner's environment, and also with them unset.
- `test_here_under_tmux_finds_the_tmux_pane_ghost` passes, whether or not the outer environment has `TMUX`.
- The worklog records the result of the confirm-first runs.
- Every check in the done check passes.
- No doc changes: this is a test-only fix.

## Out of Scope
- Runner isolation in `lib/python/run_tests.py` (ISOLATE).
- Any change to `lib/python/revive.py`.
- Other `tests/lib/python/` files (CCJJ, REST-B).
