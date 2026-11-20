# Mission: Fish test panes get their own home; fish component passes under isolation

**Date**: 20261119-142514-MST
**Task**: m-020 bold-oak

## Objective
Implement row FISH (requirement R8) of the spec `altera/specs/20261119-121426-MST-green-hermetic-test-suite-for-the-merge-gate.md`. The spec's requirements and its global rules G1 to G4 are authoritative; read it with `git show master:<path>`. Altera inserts the row's done-check block.

Revised 2026-11-20 after the mission critique (`altera/reviews/missions/m-020-critique.md`): `fish --no-config -i` writes no history, so this row is defence in depth, not a leak fix, and its test checks what can be true.

Your worktree builds on the review branch `alt/review/g-001`, which holds ISOLATE (commit `0d2046cc`; `isolated_env` and `test_home()` in `lib/python/run_tests.py`). They are not on `master` yet. Check with `git merge-base --is-ancestor 0d2046cc HEAD`; if it fails, stop and report.

## Done Check

```donecheck
{"v":1,"timeout":"15m","checks":[
 {"kind":"command","title":"fish component","run":"uv run lib/python/run_tests.py fish -v","stdout_contains":["test_an_interactive_pane_runs_in_its_own_home PASSED"],"stdout_matches":"\\b[1-9]\\d{2,} passed"}
]}
```

## Context
- `tests/fish/conftest.py`:
  - `FishPane` (class at line 44, `run` at line 53) builds the pty shell's env at line 82. It inherits `HOME` and `XDG_DATA_HOME`;
  - `SETTLE = 2.6` (line 24) makes each pty test slow. The component takes about 3 minutes, so give runs a long timeout.
- The critique probed fish 4.1.2 with `FishPane`'s exact launch (`fish --no-config -i -C "source <init>"`, temp `HOME` and XDG folders): `$fish_history` is set to empty, and no history file appears. So the panes do **not** write the operator's history today. The pane env still inherits the real `HOME`, XDG folders and anything that reads them, which is what this row closes.
- Steps:
  1. R8.1: record the probe result in the worklog (no history written; defence in depth). Prove it with a temp home only; never read the real history file. Then set `HOME`, `XDG_DATA_HOME` and `XDG_CONFIG_HOME` under the pane's own state folder. Give that pane home a `dotfiles` symlink to `DOTFILES`, as `test_home()` does: `fish/functions/revive.fish` runs `python3 ~/dotfiles/lib/python/revive.py` and sources `~/dotfiles/fish/functions/ccs.fish`, and about ten tests use the `revive_init` fixture.
     - Keep caller overrides winning. `FishPane.run` builds `dict(os.environ, TERM=..., XDG_STATE_HOME=..., **self.env)`, and `tests/fish/test_revive_nvim.py` passes `XDG_DATA_HOME` and `XDG_CONFIG_HOME` through `env=`. Adding those names as keyword arguments raises `TypeError` after `pty.fork()`, inside the child. Build the defaults in a dict first, then `update` it with `self.env`.
  2. R8.2: add the new file `tests/fish/test_pane_isolation.py` with `test_an_interactive_pane_runs_in_its_own_home(tmp_path)`: inside a pane, `$HOME`, `$XDG_DATA_HOME` and `$XDG_CONFIG_HOME` resolve under the pane's own folder below **this test's** `tmp_path`, `$HOME/dotfiles` resolves to `DOTFILES`, and `$fish_history` is empty. Compare against this test's own `tmp_path`, never against "some temp folder", so the test fails with the `FishPane` change reverted, even under the ISOLATE runner.
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
- `test_an_interactive_pane_runs_in_its_own_home` passes, and it fails with the `FishPane` env change reverted (say in the worklog that you checked this).
- The whole `fish` component passes, with over 100 tests passed.
- The worklog records the history probe result, proved with a temp home.
- Every check in the done check passes.
- No doc changes: this is a test-only fix.

## Out of Scope
- Speeding up the pty tests or `SETTLE`.
- Other components.
- The live-checkout scan (CANARY).
