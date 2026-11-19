# Mission: Remaining bin, service and lib/python components pass under isolation

**Date**: 20261119-142514-MST
**Task**: m-022 bold-pine

## Objective
Implement row REST-B (requirement R10) of the spec `altera/specs/20261119-121426-MST-green-hermetic-test-suite-for-the-merge-gate.md`. The spec's requirements and its global rules G1 to G4 are authoritative; read it with `git show master:<path>`. Altera inserts the row's done-check block.

## Done Check

```donecheck
{"v":1,"timeout":"20m","checks":[
 {"kind":"command","title":"lib/python component","run":"uv run lib/python/run_tests.py lib/python","stdout_matches":"\\b[1-9]\\d{2,} passed"},
 {"kind":"command","title":"no live git hooks","run":"uv run lib/python/run_tests.py lib/python/test_cc_worktree.py -v -k git_sees_no_live_hooks_path","stdout_contains":["test_git_sees_no_live_hooks_path PASSED"]},
 {"kind":"command","title":"cc-peers component","run":"uv run lib/python/run_tests.py bin/cc-peers","stdout_matches":"\\b[1-9]\\d* passed"},
 {"kind":"command","title":"scratch component","run":"uv run lib/python/run_tests.py bin/scratch","stdout_matches":"\\b[1-9]\\d* passed"},
 {"kind":"command","title":"ytdl component","run":"uv run lib/python/run_tests.py bin/ytdl","stdout_matches":"\\b[1-9]\\d* passed"},
 {"kind":"command","title":"exocortex component","run":"uv run lib/python/run_tests.py bin/exocortex-id","stdout_matches":"\\b[1-9]\\d* passed"},
 {"kind":"command","title":"server-check component","run":"uv run lib/python/run_tests.py services/server_check","stdout_matches":"\\b[1-9]\\d* passed"},
 {"kind":"command","title":"youtube component","run":"uv run lib/python/run_tests.py yt","stdout_matches":"\\b[1-9]\\d+ passed"}
]}
```

## Context
- R10.1: run each component under ISOLATE's runner, then fix it or record a reason in `docs/testing.md`. The components are `bin/cc-peers`, `bin/scratch`, `bin/ytdl`, `bin/exocortex-id`, `services/server_check`, `services/youtube_transcribe` (alias `yt`) and `lib/python`.
- What the spec's audit found:
  - `bin/scratch` and `services/server_check` are clean;
  - `ytdl` sets `HOME` in 3 places;
  - `ytdl`, `exocortex-id` and `youtube_transcribe` were not inspected in depth;
  - the `cc-peers` tests make temp git repos with an identity, but `git commit` ran the live `~/dotfiles/git/hooks` through `hooksPath` (`rcs/gitconfig` line 6). ISOLATE's `GIT_CONFIG_GLOBAL` now replaces that setting.
- R10.2:
  - confirm that `cc-peers`, `tests/lib/python/test_cc_worktree.py` and `tests/hooks/test_cc_worktree_nudge.py` pass without those hooks;
  - add `test_git_sees_no_live_hooks_path` to `tests/lib/python/test_cc_worktree.py`. Under the runner, `git config --global --get core.hooksPath` prints nothing.
- R10.3: HOOKS owns `tests/hooks/test_cc_worktree_nudge.py`, so only confirm that it passes.
- CCJJ already fixed `test_ccjj.py`. Leave it alone unless the lib/python run shows it failing; then report that.
- An `isolation: False` opt-out with a reason may go in `lib/python/run_tests.py`, and only that edit.

## Constraints
- You work in a git worktree. Use `git`; `jj`, `g`, `commit-mine` and `ccjj` are denied. Never push.
- Run tests with `uv run lib/python/run_tests.py <component or file>` from the worktree root, never `cmds test` (it tests ~/dotfiles, not your tree).
- Tests are hermetic: no test touches the real HOME, ~/.config, ~/Library/LaunchAgents, ~/.claude, a live tmux server or a running service. Git and jj run only in temp repositories with an explicit identity.
- Never use `rm`; use `trash`. Never write a secret or private detail into a tracked file: the repository is public.
- Scope: those components' test folders and `tests/lib/python/` except `test_revive.py`; `lib/python/run_tests.py` for an opt-out only; and `docs/testing.md`. No product or live file changes.

## Success Criteria
- All seven components pass under isolation, or carry a written opt-out reason in `docs/testing.md`.
- `test_git_sees_no_live_hooks_path` passes.
- Every check in the done check passes.

## Out of Scope
- `tests/bin/astro/` (ASTRO), `tests/lib/python/test_revive.py` (REVIVE) and `tests/hooks/` (HOOKS).
- Timing (TIMING).
- Shared-file order: REST-B edits `lib/python/run_tests.py` and `docs/testing.md` after REST-A and before TIMING.
