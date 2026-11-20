# Worklog: Fish test panes get their own home

**Date**: 20261120-160928-MST
**Task**: m-020
**Agent**: w-40

## Summary

Row FISH (R8) of the hermetic-test-suite spec.

- `FishPane.run` (`tests/fish/conftest.py`) now gives each pty shell its own home
  at `<state folder>/pane-home`: `HOME`, `XDG_CONFIG_HOME=<home>/.config` and
  `XDG_DATA_HOME=<home>/.local/share`. `FishPane.home()` makes the folders and a
  `dotfiles` symlink to `DOTFILES`, as the runner's `test_home()` does, so
  `revive.fish`'s `~/dotfiles/...` paths reach the tree under test. The env is
  built as a dict of defaults, then `update(self.env)`, so caller overrides
  (`test_revive_nvim.py`'s XDG folders) still win and no duplicate-keyword
  `TypeError` can fire inside the forked child. The folder is named `pane-home`,
  not `home`, because `test_trash.py` already uses `tmp_path / "home"`.
- New `tests/fish/test_pane_isolation.py::test_an_interactive_pane_runs_in_its_own_home`:
  inside a pane, `$HOME` is exactly `<this test's tmp_path>/pane-home`, both XDG
  folders sit under it, `realpath $HOME/dotfiles` is `DOTFILES`, and
  `$fish_history` is empty.

**R8.1 history probe (fish 4.1.2).** Ran FishPane's exact launch
(`fish --no-config -i -C "source <init>"`) with a `tempfile.TemporaryDirectory`
as state folder, so HOME and every XDG folder were temporary. Typed
`echo probe-marker-xyz`, printed `$fish_history`, ran `history save`, exited.
Result: `$fish_history` is empty, no file whose name contains `history` exists
anywhere under the temp folder, and no file there contains the marker. So the
panes never wrote the operator's history; this row is defence in depth (the pane
env no longer inherits the real or runner HOME/XDG folders), not a leak fix. The
real history file was never read.

**Revert check.** With the three `HOME`/`XDG_*` lines removed from the pane env,
the new test fails: `$HOME` was the runner's `dotfiles-test-home-*`, not
`<tmp_path>/pane-home`. Restored, it passes.

**R8.3.** `uv run lib/python/run_tests.py fish -v` under ISOLATE's runner:
173 passed in 206 s. No `.fish` file changed. The CANARY-pinned lines in
`test_cc_worktree_wrapper.py` and `test_trash.py` are untouched.

## How It Went

Smooth. The brief had already worked out the two traps (the caller-override
`TypeError` after `pty.fork()`, and comparing against this test's own
`tmp_path`), so the change was small. No other fish test depended on the pane
inheriting HOME.

## System Learnings

- Under the ISOLATE runner HOME is already a throwaway, so a check like "HOME is
  in some temp folder" passes with or without the pane change; only an exact
  comparison with the test's own `tmp_path` catches the revert.
- Typed lines echo back in the pty output, so a marker regex matches the typed
  `$HOME` too; take the last match.

## Process Improvements

None needed; the critique-revised brief was accurate and complete.

## Self-Improvement Notes

Did the probe with the new `FishPane` itself pointed at a temp folder, which
proves the same launch the tests use without touching the real home.
