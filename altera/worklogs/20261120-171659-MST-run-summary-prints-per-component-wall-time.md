# Worklog: Run summary prints per-component wall time

**Date**: 20261120-171659-MST
**Task**: m-023
**Agent**: w-48

## Summary

Row TIMING (R11) of the hermetic-test-suite spec.

- `lib/python/run_tests.py`: `run_all` and `run_many` time each component with
  `time.monotonic()`; result rows are now a 4-tuple (`Result` alias). `print_summary`
  ends each component line, and the total line (PASSED or FAILED form), with
  `  [N.Ns]` via `format_seconds`. The total is the sum of component times.
- `tests/lib/python/test_run_tests.py`: `test_summary_shows_each_components_time`
  (run_many path, fake clock, one failing component so the FAILED total line is
  covered) and `test_run_all_times_each_component_and_the_total` (run_all path).
- `docs/testing.md`: new "Run time" section — how to read the times, the 14 min /
  3 min fish figures, and the per-component test-count table from the spec.

Both done-check commands pass locally: 31 tests in `test_run_tests.py`, and the
two-component run prints `PASS  bin/exocortex-id  64 passed  [0.4s]`.

## How It Went

Straightforward. Done directly rather than via subagents: three small edits in
files already read for orientation, so delegation would have cost more context
than it saved.

## System Learnings

- `run_many` with a single group returns without a summary, so any check of the
  summary format needs two components (the done check already accounts for this).
- The spec's table counts `exocortex-id` at 37 test functions, but a run reports 64
  passed; parametrize explains the gap, as the table's caption says.

## Process Improvements

None needed; the brief pinned the exact output format and the regex, which made
the target unambiguous.

## Self-Improvement Notes

A fake `time.monotonic` driven by an iterator is a tidy way to make timing output
exact in tests; watch for round-half-even in `:.1f` (0.25 → "0.2") when choosing
readings.
