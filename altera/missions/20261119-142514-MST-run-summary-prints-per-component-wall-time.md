# Mission: Run summary prints per-component wall time

**Date**: 20261119-142514-MST
**Task**: m-023 bold-rain

## Objective
Implement row TIMING (requirement R11) of the spec `altera/specs/20261119-121426-MST-green-hermetic-test-suite-for-the-merge-gate.md`. The spec's requirements and its global rules G1 to G4 are authoritative; read it with `git show master:<path>`. Altera inserts the row's done-check block.

## Done Check

```donecheck
{"v":1,"timeout":"5m","checks":[
 {"kind":"command","title":"summary test","run":"uv run lib/python/run_tests.py lib/python/test_run_tests.py -v","stdout_contains":["test_summary_shows_each_components_time PASSED"]},
 {"kind":"command","title":"recorded two-component run","record":true,"run":"uv run lib/python/run_tests.py bin/exocortex-id services/server_check","stdout_matches":"PASS\\s+bin/exocortex-id[^\\n]*  \\[\\d+\\.\\ds\\]"}
]}
```

## Context
- `lib/python/run_tests.py`:
  - `print_summary` (line 279 on the spec's base; re-check after ISOLATE, REST-A and REST-B) prints each line as two spaces, the status, two spaces, the padded name, two spaces and the detail;
  - `run_all` (line 314) and `run_many` (line 385) build the results list;
  - `run_many`'s single-group path returns without a summary, so the recorded check runs two components.
- R11.1:
  - time each component with `time.monotonic()` in `run_all` and `run_many`;
  - end each component's summary line with two spaces and the wall time: seconds with one decimal and an `s`, in square brackets, such as `[12.3s]`;
  - the last line gives the total in the same form.
- The recorded check matches the PASS line of `bin/exocortex-id`, followed by that bracket.
- R11.2: add `test_summary_shows_each_components_time` to `tests/lib/python/test_run_tests.py`.
- R11.3: add a Run time section to `docs/testing.md`. It says how to read the times and gives the known figures from the spec's Technical Approach:
  - the full run takes about 14 minutes;
  - `fish` takes about 3 minutes, because of the 2.6 s `SETTLE` in `tests/fish/conftest.py`;
  - the per-component test counts.
  The operator's later GATE-RUN step adds the measured seconds.

## Constraints
- You work in a git worktree. Use `git`; `jj`, `g`, `commit-mine` and `ccjj` are denied. Never push.
- Run tests with `uv run lib/python/run_tests.py <component or file>` from the worktree root, never `cmds test` (it tests ~/dotfiles, not your tree).
- Tests are hermetic: no test touches the real HOME, ~/.config, ~/Library/LaunchAgents, ~/.claude, a live tmux server or a running service.
- Never use `rm`; use `trash`. Never write a secret or private detail into a tracked file: the repository is public.
- This is not a live path: the runner runs only under `cmds test` and the gate.

## Success Criteria
- `test_summary_shows_each_components_time` passes, and the earlier `test_run_tests.py` tests still pass.
- A two-component run prints each component's time and the total in the required form.
- `docs/testing.md` has the Run time section.
- Every check in the done check passes.

## Out of Scope
- A parallel `--jobs` mode or a faster gate target (the spec's first Open Question).
- Recording measured times (the operator's GATE-RUN step).
- The guard tests (CANARY).
