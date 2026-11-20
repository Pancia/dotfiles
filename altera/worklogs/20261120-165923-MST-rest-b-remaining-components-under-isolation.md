# Worklog: REST-B: remaining components under isolation

**Date**: 20261120-165923-MST
**Task**: m-022
**Agent**: w-45

## Summary

Ran all seven REST-B components under the isolating runner. Six passed as they
were: `bin/cc-peers` (14), `bin/scratch` (48), `bin/ytdl` (54),
`bin/exocortex-id` (64), `services/server_check` (10), `lib/python` (473 passed,
1 strict xfail in `test_ccjj.py`, which is pre-existing and not ours).

`yt` failed 4 tests with `FileNotFoundError` on
`<throwaway home>/.local/state/youtube-transcribe/jobs/test*.json`. Cause:
`server.py` computes `JOBS_DIR` (and the storage/state/logs folders) from
`Path.home()` at import, and a stream run to its end calls `persist_job`. Before
isolation those tests wrote `test123.json` and `test456.json` into the real
`~/.local/state/youtube-transcribe/jobs/` — both files are still there, dated
Nov 19 (left in place: live state is out of scope, the operator can trash them).
Fix: new autouse `tests/services/youtube_transcribe/conftest.py` that points
`STORAGE_DIR`, `TRANSCRIPTS_DIR`, `SUMMARIES_DIR`, `STATE_DIR`, `LOGS_DIR`,
`JOBS_DIR` and `TEMP_DIR` into `tmp_path`, plus a test that `persist_job` lands
there. `yt` now 128 passed.

R10.2: added `test_git_sees_no_live_hooks_path` to `test_cc_worktree.py`. It
passes under the runner; outside it, `git config --global --get core.hooksPath`
prints `~/dotfiles/git/hooks`, so the test discriminates. `cc-peers`,
`test_cc_worktree.py` and `hooks/test_cc_worktree_nudge.py` (18 passed) all pass
with the hooks gone. No opt-out was needed; `lib/python/run_tests.py` untouched.
Docs: a REST-B list under "Isolation" in `docs/testing.md`.

## How It Went

Smooth. Running the six small components in parallel first gave the whole
picture in one step; only `yt` needed work and its error named the folder.

## System Learnings

- Module-level `Path.home()` constants are the recurring leak: isolation turns a
  silent real-home write into a loud `FileNotFoundError`, which is the point.
- `server.py` still makes `/tmp/youtube-transcribe` on import; harmless (not
  home) and fixing it would be a product change.

## Process Improvements

- The spec's audit listed `yt` as "not inspected in depth"; a grep for
  `Path.home()` at module level in product code would have found this up front.

## Self-Improvement Notes

- Check for leftovers of an old leak in the real home (read-only) to confirm a
  cause, rather than inferring it.
