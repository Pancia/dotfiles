# Mission: roleplay, mods and lua pass under isolation

**Date**: 20261119-142514-MST
**Task**: m-021 bold-peak

## Objective
Implement row REST-A (requirement R9) of the spec `altera/specs/20261119-121426-MST-green-hermetic-test-suite-for-the-merge-gate.md`. The spec's requirements and its global rules G1 to G4 are authoritative; read it with `git show master:<path>`. Altera inserts the row's done-check block.

## Done Check

```donecheck
{"v":1,"timeout":"15m","checks":[
 {"kind":"command","title":"roleplay component","run":"uv run lib/python/run_tests.py roleplay -v","stdout_contains":["test_roll_sees_a_throwaway_home PASSED"],"stdout_matches":"\\b[1-9]\\d+ passed"},
 {"kind":"command","title":"mods component","run":"uv run lib/python/run_tests.py mods -v","stdout_matches":"test_mod_suite_passes\\[[^\\]]+\\] PASSED"},
 {"kind":"command","title":"lua component","run":"uv run lib/python/run_tests.py lib/lua","stdout_matches":"\\b[12][0-9] passed(, \\d+ warnings?)? in "}
]}
```

## Context
- `roleplay` runs from `roleplay/tests/` through the `tests/roleplay` symlink (its `COMPONENTS` entry is at line 93 of `lib/python/run_tests.py`). R9.1:
  - `_roll` (line 699 of `roleplay/tests/test_roleplay_roll.py`) passes `HOME` from `Path.home()` (line 705). `roleplay/tests/test_roleplay_say.py` does the same at lines 59 and 120. Pass a `tmp_path` home instead;
  - the module-level `_FAKE_HOME = Path(tempfile.mkdtemp(...))` (line 30) leaks a folder on every run. Replace it with a session fixture built from `tmp_path_factory`;
  - add `test_roll_sees_a_throwaway_home`. It runs a small stub script through `_roll`, because the real `roleplay-roll` does not print `HOME`. It asserts that the `HOME` the stub saw equals that test's own `tmp_path` home. A temp folder alone is not enough, because the runner already gives one.
- `mods` (entry at line 129) runs `claude plugin test` from `test_mod_suite_passes` (line 31 of `tests/mods/test_mod_suites.py`). R9.2:
  - run it under the isolated home;
  - if it fails only because of the fake home, set `isolation: False` with an `isolation_reason` on `mods`, and record the failure in `docs/testing.md`;
  - precondition: `claude` is on `PATH`. Without it the tests skip and the mods check fails. Report that instead of weakening the check.
- `lib/lua` (R9.3): confirm it passes under isolation. No change is expected, because `harness.lua` takes its own paths. Precondition: `lua5.4` is installed; without it every lua test skips. Report rather than work around it.
- ISOLATE added the opt-out keys and the Isolation section of `docs/testing.md`.

## Constraints
- You work in a git worktree. Use `git`; `jj`, `g`, `commit-mine` and `ccjj` are denied. Never push.
- Run tests with `uv run lib/python/run_tests.py <component or file>` from the worktree root, never `cmds test` (it tests ~/dotfiles, not your tree).
- Tests are hermetic: no test touches the real HOME, ~/.config, ~/Library/LaunchAgents, ~/.claude, a live tmux server or a running service.
- Never use `rm`; use `trash`. Never write a secret or private detail into a tracked file: the repository is public.
- Change only `roleplay/tests/`, the opt-out keys in `lib/python/run_tests.py`, and `docs/testing.md`.
- `roleplay/bin/` and `ai/mods/` are live: the roll runs on every prompt, and mods hot-reload in every session. Do not edit them.

## Success Criteria
- The roleplay component passes, including `test_roll_sees_a_throwaway_home`. No test passes the real home, and no folder leaks.
- The mods suites pass, under isolation or under a written opt-out recorded in `docs/testing.md`.
- The lua component passes.
- Every check in the done check passes.

## Out of Scope
- The remaining components (REST-B).
- Timing (TIMING).
- Shared-file order: REST-A edits `lib/python/run_tests.py` (opt-out only) and `docs/testing.md` after ISOLATE and before REST-B and TIMING.
