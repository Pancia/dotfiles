# Mission: ccjj tests own their home, lock folder and jj identity

**Date**: 20261119-142514-MST
**Task**: m-019 bold-moth

## Objective
Implement row CCJJ (requirement R7) of the spec `altera/specs/20261119-121426-MST-green-hermetic-test-suite-for-the-merge-gate.md`. The spec's requirements and its global rules G1 to G4 are authoritative; read it with `git show master:<path>`. Altera inserts the row's done-check block.

Revised 2026-11-20 after the mission critique (`altera/reviews/missions/m-019-critique.md`): the fixture covers every variable and every call site, a second real-home leak is in scope, and the new tests can tell the file's own fixture from the ISOLATE runner.

## Done Check

```donecheck
{"v":1,"timeout":"15m","checks":[
 {"kind":"command","title":"ccjj file","run":"uv run lib/python/run_tests.py lib/python/test_ccjj.py -v","stdout_contains":["test_the_shared_lock_is_under_the_test_home PASSED","test_jj_repo_config_stays_in_the_test_home PASSED"],"stdout_matches":"\\b[1-9]\\d{2,} passed"}
]}
```

## Context
- Your worktree must contain the ISOLATE work (commit `0d2046cc`, on the review branch `alt/review/g-001`, not yet on `master`). Check with `git merge-base --is-ancestor 0d2046cc HEAD`. If it is missing, stop and report; do not rebuild the runner isolation.
- Under the ISOLATE runner, `isolated_env` (`lib/python/run_tests.py`) already gives every pytest a throwaway `HOME`, XDG folders and jj identity. This file must stay hermetic **without** that runner too, so its own fixture must win, and its tests must prove that.
- `lib/python/ccjj.py`: the lock helpers place the lock folder at `~/.local/state/ai-jj-commit` through `os.path.expanduser` (around lines 283, 702 and 2888; the file is being edited elsewhere, so lines may move). `journal_root()` reads `XDG_STATE_HOME` when `CC_JJ_JOURNAL` is unset. Do not change `ccjj.py`.
- `tests/lib/python/test_ccjj.py`:
  - jj runs with the inherited environment in `Repo.__init__`, `Repo.commit`, `Repo.run`, `Repo.jj_` and several direct `subprocess` calls, and ccjj runs with `{**os.environ, ...}` in many tests. Setting the variables in one autouse fixture covers all of them; no call site needs its own case.
  - The lock tests `test_diff_mode_also_releases_the_lock`, `test_commit_refuses_while_the_shared_lock_is_held` and `test_audit_backs_off_while_a_commit_is_in_flight` expand `~/.local/state/ai-jj-commit/<repo>.lock`, so on `master` they create and delete files in the real home.
  - **Second leak:** `test_a_new_file_over_the_size_limit_still_fails_closed` runs `jj config set --repo`, which leaves a per-repo entry in the real `~/.config/jj/repos`. Confirm which variable governs that folder (most likely `XDG_CONFIG_HOME`, or jj's own config-dir rule on macOS) before relying on it.
- The file has about 214 tests that call jj. Record the run time in the worklog; if it is over 12 minutes, say so, so the timeout can be raised.

## Requirements (R7, as revised)
- R7.1 One autouse fixture in `test_ccjj.py` sets, with `monkeypatch.setenv`: `HOME` to `tmp_path / "home"`; `XDG_CONFIG_HOME`, `XDG_DATA_HOME`, `XDG_STATE_HOME` and `XDG_CACHE_HOME` to the standard folders under it; `JJ_CONFIG` to a config file it writes there with a `[user]` table; `JJ_USER` and `JJ_EMAIL`. It creates those folders. Every subprocess then inherits them.
- R7.2 `test_the_shared_lock_is_under_the_test_home(tmp_path)`: the lock path ccjj computes equals the path under **this test's** `tmp_path / "home"`. Under the ISOLATE runner alone it would point at the runner's home instead, so this test fails if the fixture is missing.
- R7.3 `test_jj_repo_config_stays_in_the_test_home(tmp_path)`: run `jj config set --repo` in a temp repo, then assert that the per-repo entry is under this test's `tmp_path / "home"`, and that no entry appeared under the folder the operator's real config would use (compute it from `pwd.getpwuid(os.getuid()).pw_dir`, read only, and compare entry counts before and after; never write there).

## Constraints
- You work in a git worktree. Use `git`; `jj`, `g`, `commit-mine` and `ccjj` are denied. Never push. jj may run only inside temporary test repositories, with an explicit identity.
- Run tests with `uv run lib/python/run_tests.py <component or file>` from the worktree root, never `cmds test` (it tests ~/dotfiles, not your tree).
- Tests are hermetic: no test touches the real HOME, ~/.config, ~/Library/LaunchAgents, ~/.claude, a live tmux server or a running service. R7.3 may only read the real config folder, to count entries.
- Never use `rm`; use `trash`. Never write a secret or private detail into a tracked file: the repository is public.
- Only `tests/lib/python/test_ccjj.py` changes. No live path is touched.

## Success Criteria
- `test_the_shared_lock_is_under_the_test_home` and `test_jj_repo_config_stays_in_the_test_home` pass.
- The whole `test_ccjj.py` file passes, with over 100 tests passed.
- After a run of this file, the operator's real `~/.config/jj/repos` gains no entry, and `~/.local/state/ai-jj-commit` gains no lock.
- Every check in the done check passes.
- No doc changes: this is a test-only fix.

## Out of Scope
- `lib/python/ccjj.py` and its lock location.
- Other `tests/lib/python/` files (REVIVE, REST-B).
- Cleaning up the entries earlier test runs already left in the real `~/.config/jj/repos` (an operator task).
