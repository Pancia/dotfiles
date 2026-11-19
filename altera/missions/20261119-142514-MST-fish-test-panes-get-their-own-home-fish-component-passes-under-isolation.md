# Mission: Fish test panes get their own home; fish component passes under isolation

**Date**: 20261119-142514-MST
**Task**: m-020 bold-oak

## Objective
Implement row FISH (requirement R8) of the spec `altera/specs/20261119-121426-MST-green-hermetic-test-suite-for-the-merge-gate.md`. The spec's requirements and its global rules G1 to G4 are authoritative; read it with `git show master:<path>`. Altera inserts the row's done-check block.

## Done Check

```donecheck
{"v":1,"timeout":"15m","checks":[
 {"kind":"command","title":"fish component","run":"uv run lib/python/run_tests.py fish -v","stdout_contains":["test_an_interactive_pane_writes_history_only_in_its_own_home PASSED"],"stdout_matches":"\\b[1-9]\\d{2,} passed"}
]}
```

## Context
- `tests/fish/conftest.py`:
  - `FishPane` (class at line 44, `run` at line 53) builds the pty shell's env at line 82. It inherits `HOME` and `XDG_DATA_HOME`;
  - `SETTLE = 2.6` (line 24) makes each pty test slow. The component takes about 3 minutes, so give runs a long timeout.
- Interactive fish writes `$XDG_DATA_HOME/fish/fish_history` even with `--no-config`, so the panes likely write test commands into the operator's history today.
- Steps:
  1. R8.1: confirm this first. Do not read or quote the real history file; test inside the isolated runner, or with a temp home of your own. Then set `HOME`, `XDG_DATA_HOME` and `XDG_CONFIG_HOME` under the pane's own state folder.
  2. R8.2: add the new file `tests/fish/test_pane_isolation.py` with `test_an_interactive_pane_writes_history_only_in_its_own_home`.
  3. R8.3: make the whole `fish` component pass under ISOLATE's runner.
- No `.fish` file is expected to change. If one does, load the `/fish` skill first, keep the Fish Shell Gotchas in CLAUDE.md, and make sure it passes `fish -n`.
- CANARY's allowlist pins exact lines that name the live checkout:
  - `tests/fish/test_cc_worktree_wrapper.py`, lines 13 and 191;
  - `tests/fish/test_trash.py`, line 24.
  Leave those lines' text alone. If you must change one, say so in the worklog.

## Constraints
- You work in a git worktree. Use `git`; `jj`, `g`, `commit-mine` and `ccjj` are denied. Never push.
- Run tests with `uv run lib/python/run_tests.py <component or file>` from the worktree root, never `cmds test` (it tests ~/dotfiles, not your tree).
- Tests are hermetic: no test touches the real HOME, ~/.config, ~/Library/LaunchAgents, ~/.claude, a live tmux server or a running service.
- Never use `rm`; use `trash`. Never write a secret or private detail into a tracked file: the repository is public.
- Only `tests/fish/` changes. `fish/functions/` and `fish/conf.d/` are live paths and must not change.

## Success Criteria
- `test_an_interactive_pane_writes_history_only_in_its_own_home` passes.
- The whole `fish` component passes, with over 100 tests passed.
- The worklog records whether the panes wrote to the real history before the fix.
- Every check in the done check passes.
- No doc changes: this is a test-only fix.

## Out of Scope
- Speeding up the pty tests or `SETTLE`.
- Other components.
- The live-checkout scan (CANARY).
