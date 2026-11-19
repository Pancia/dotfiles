# Mission: Guard tests: throwaway home, linked tree, no live-checkout paths; remove the interim notice

**Date**: 20261119-142514-MST
**Task**: m-024 bold-reef

## Objective
Implement row CANARY (requirement R12) of the spec `altera/specs/20261119-121426-MST-green-hermetic-test-suite-for-the-merge-gate.md`. The spec's requirements and its global rules G1 to G4 are authoritative; read it with `git show master:<path>`. Altera inserts the row's done-check block.

## Done Check

```donecheck
{"v":1,"timeout":"5m","checks":[
 {"kind":"command","title":"hermetic guard","run":"uv run lib/python/run_tests.py lib/python/test_hermetic_env.py -v","stdout_contains":["test_home_is_a_throwaway PASSED","test_dotfiles_in_home_is_the_tree_under_test PASSED","test_no_test_names_the_live_checkout PASSED"]},
 {"kind":"command","title":"interim notice removed","run":"if grep -q 'until HOOKS, ASTRO and REST-A land' docs/testing.md CLAUDE.md; then echo notice-present; exit 1; else echo notice-removed; fi","stdout_contains":["notice-removed"]}
]}
```

## Context
- R12.1: add the new file `tests/lib/python/test_hermetic_env.py` with three tests:
  - `test_home_is_a_throwaway`: `HOME` differs from `pwd.getpwuid(os.getuid()).pw_dir` and lies under the system temp folder. Resolve symlinks on both sides, because macOS has `/var` and `/private/var`;
  - `test_dotfiles_in_home_is_the_tree_under_test`: `HOME/dotfiles` resolves to the repository root;
  - `test_no_test_names_the_live_checkout`: scan `tests/**/*.py` and `roleplay/tests/*.py` for the three patterns R12.1 lists. Those are `Path.home()` joined with `dotfiles`, the tilde form `~/dotfiles`, and the `$HOME/dotfiles` form. Skip lines whose first non-space character is `#`, and skip this file itself.
- The allowlist is keyed by file and the exact stripped line text, never by pattern. A new live-path line in an allowlisted file must still fail. Give each entry a one-line reason. Start entries, verified on master before the deps merged (re-check them now):
  - `tests/fish/test_cc_worktree_wrapper.py`, lines 13 and 191. Lines 81 and 89 are comments the scan skips. The file guards against the live checkout, so it must name it;
  - `tests/fish/test_trash.py`, line 24: the same guard;
  - `tests/lib/python/test_cc_worktree.py`, line 152: a docstring;
  - `tests/lib/python/test_llm_output.py`, lines 694, 705 and 787: docstrings and input strings the code under test must handle. Line 709 is a comment.
- ASTRO removed the live path from `tests/bin/astro/conftest.py`, and HOOKS removed `Path.home()` from `tests/hooks/test_ensure_rcs.py`.
- If the scan still finds a line that names the live checkout only as documentation, allowlist it with that reason. Do not edit files outside this mission's scope.
- R12.2: in `docs/testing.md`, say that a bare `pytest` fails `test_home_is_a_throwaway` on purpose.
- R12.3: remove the interim-red notice that ISOLATE added to `docs/testing.md` and to the `### Testing` section of `CLAUDE.md`. Its key phrase is `until HOOKS, ASTRO and REST-A land`. The check requires that phrase to be gone from both files.

## Constraints
- You work in a git worktree. Use `git`; `jj`, `g`, `commit-mine` and `ccjj` are denied. Never push.
- Run tests with `uv run lib/python/run_tests.py <component or file>` from the worktree root, never `cmds test` (it tests ~/dotfiles, not your tree).
- Tests are hermetic: no test touches the real HOME, ~/.config, ~/Library/LaunchAgents, ~/.claude, a live tmux server or a running service.
- Never use `rm`; use `trash`. Never write a secret or private detail into a tracked file: the repository is public.
- Change only `tests/lib/python/test_hermetic_env.py`, `docs/testing.md`, and the notice in `CLAUDE.md`. No live path is touched.

## Success Criteria
- The three guard tests pass under the runner.
- The allowlist is keyed by file and exact line, with a reason for each entry.
- `docs/testing.md` documents the bare-pytest canary.
- The interim notice is gone from `docs/testing.md` and `CLAUDE.md`.
- Every check in the done check passes.

## Out of Scope
- Fixing components (earlier rows).
- Running the full gate from a fresh clone and recording times (the operator's GATE-RUN step).
- Turning the merge gate on.
