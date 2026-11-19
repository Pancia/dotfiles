# Mission: ccjj tests own their home, lock folder and jj identity

**Date**: 20261119-142514-MST
**Task**: m-019 bold-moth

## Objective
Implement row CCJJ (requirement R7) of the spec `altera/specs/20261119-121426-MST-green-hermetic-test-suite-for-the-merge-gate.md`. The spec's requirements and its global rules G1 to G4 are authoritative; read it with `git show master:<path>`. Altera inserts the row's done-check block.

## Done Check

```donecheck
{"v":1,"timeout":"10m","checks":[
 {"kind":"command","title":"ccjj file","run":"uv run lib/python/run_tests.py lib/python/test_ccjj.py -v","stdout_contains":["test_the_shared_lock_is_under_the_test_home PASSED"],"stdout_matches":"\\b[1-9]\\d{2,} passed"}
]}
```

## Context
- `lib/python/ccjj.py` places its lock folder at `~/.local/state/ai-jj-commit` through `os.path.expanduser` (lines 283, 702 and 2888). Do not change it.
- `tests/lib/python/test_ccjj.py`:
  - `Repo` (class at line 33, `__init__` at 36, `run` at 67) runs jj with the real config and identity;
  - the lock tests expand `~/.local/state/ai-jj-commit/<repo>.lock` at lines 1276, 1288, 1299 and 1957, so today they create and delete files in the real home.
- R7.1:
  - an autouse fixture sets `HOME` to `tmp_path / home`;
  - `Repo.__init__` and `Repo.run` pass `JJ_USER`, `JJ_EMAIL` and a `JJ_CONFIG` file;
  - the lock tests then resolve under that home.
- R7.2: add `test_the_shared_lock_is_under_the_test_home`.
- The file has about 214 tests that call jj, so expect several minutes per run.
- ISOLATE has merged. Your fixture must hold even under a bare runner.

## Constraints
- You work in a git worktree. Use `git`; `jj`, `g`, `commit-mine` and `ccjj` are denied. Never push. jj may run only inside temporary test repositories, with an explicit identity.
- Run tests with `uv run lib/python/run_tests.py <component or file>` from the worktree root, never `cmds test` (it tests ~/dotfiles, not your tree).
- Tests are hermetic: no test touches the real HOME, ~/.config, ~/Library/LaunchAgents, ~/.claude, a live tmux server or a running service.
- Never use `rm`; use `trash`. Never write a secret or private detail into a tracked file: the repository is public.
- Only `tests/lib/python/test_ccjj.py` changes. No live path is touched.

## Success Criteria
- `test_the_shared_lock_is_under_the_test_home` passes.
- The whole `test_ccjj.py` file passes, with over 100 tests passed.
- Every check in the done check passes.
- No doc changes: this is a test-only fix.

## Out of Scope
- `lib/python/ccjj.py` and its lock location.
- Other `tests/lib/python/` files (REVIVE, REST-B).
