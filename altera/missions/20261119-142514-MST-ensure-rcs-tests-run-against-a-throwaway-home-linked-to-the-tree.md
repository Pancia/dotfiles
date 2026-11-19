# Mission: ensure-rcs tests run against a throwaway home linked to the tree

**Date**: 20261119-142514-MST
**Task**: m-018 bold-mesa

## Objective
Implement row HOOKS (requirement R6) of the spec `altera/specs/20261119-121426-MST-green-hermetic-test-suite-for-the-merge-gate.md`. The spec's requirements and its global rules G1 to G4 are authoritative; read it with `git show master:<path>`. Altera inserts the row's done-check block.

## Done Check

```donecheck
{"v":1,"timeout":"8m","checks":[
 {"kind":"command","title":"hooks component","run":"uv run lib/python/run_tests.py hooks -v","stdout_contains":["test_reads_the_manifest_of_the_tree_under_test PASSED"],"stdout_matches":"\\b[1-9]\\d+ passed"}
]}
```

## Context
- `rcs/claude-ensure-rcs-hook.sh` reads `$HOME/dotfiles/rcs/MANIFEST` (line 12). Do not edit it: it runs in every Claude session.
- `tests/hooks/test_ensure_rcs.py`:
  - `run_hook` (line 15) inherits `HOME`. The `TestPreMode` cases (class at line 27) build paths from `Path.home()` (lines 34 to 100);
  - `run_hook_home` (line 105) already shows the home-passing pattern;
  - `run_hook_raw` is at line 212. `TestJsonParsing.DST` (line 223) is computed at import time, and line 239 symlinks `Path.home() / .config/tmux`.
- R6.1:
  - `run_hook` and `run_hook_raw` always pass a throwaway `HOME`, built by a fixture that links `dotfiles` to `DOTFILES`;
  - the fixture creates the destinations the tests name: `.config/tmux/tmux.conf`, `.config/fish/config.fish`, `.claude/CLAUDE.md`, `.claude/hooks/ensure-rcs.sh` and `Library/LaunchAgents/org.pancia.vpc.plist`;
  - replace every `Path.home()`, and make `DST` fixture-based.
- R6.2: add `TestPreMode::test_reads_the_manifest_of_the_tree_under_test`. It takes the first non-comment entry of `DOTFILES/rcs/MANIFEST` and asserts that its destination is blocked.
- R6.3: make the rest of the `hooks` component pass under ISOLATE's runner.
- This mission owns any change to `tests/hooks/test_cc_worktree_nudge.py` (R10.3). If it fails under isolation, for example because git no longer runs the live hooks, fix it here.
- ISOLATE has merged. Read its Isolation section in `docs/testing.md`.

## Constraints
- You work in a git worktree. Use `git`; `jj`, `g`, `commit-mine` and `ccjj` are denied. Never push.
- Run tests with `uv run lib/python/run_tests.py <component or file>` from the worktree root, never `cmds test` (it tests ~/dotfiles, not your tree).
- Tests are hermetic: no test touches the real HOME, ~/.config, ~/Library/LaunchAgents, ~/.claude, a live tmux server or a running service.
- Never use `rm`; use `trash`. Never write a secret or private detail into a tracked file: the repository is public.
- Only `tests/hooks/` changes. `rcs/claude-ensure-rcs-hook.sh` and every other `rcs/` file stay untouched, because they are live.

## Success Criteria
- `test_reads_the_manifest_of_the_tree_under_test` passes.
- No `Path.home()` remains in `test_ensure_rcs.py`.
- The whole `hooks` component passes under the isolating runner.
- Every check in the done check passes.
- No doc changes: this is a test-only fix.

## Out of Scope
- Any change to the live hook or `rcs/`.
- The other components (REST-A, REST-B).
- The static live-path scan (CANARY).
