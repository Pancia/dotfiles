# Worklog: CANARY: hermetic-env guard tests, interim notice removed

**Date**: 20261120-172731-MST
**Task**: m-024
**Agent**: w-51

## Summary

Added `tests/lib/python/test_hermetic_env.py` (R12.1): `test_home_is_a_throwaway`,
`test_dotfiles_in_home_is_the_tree_under_test`, `test_no_test_names_the_live_checkout`,
plus two small extras: `test_allowlist_has_no_stale_entries` (an entry that no longer
matches a line fails) and `test_scan_catches_each_spelling` (the regex matches all three
spellings). The allowlist is keyed by (file, exact stripped line) with a reason per entry.
Documented the guard and the bare-pytest canary in `docs/testing.md` "Isolation" (R12.2),
and removed the interim-red notice from `docs/testing.md` and CLAUDE.md (R12.3).

## How It Went

Smooth. The brief's starting allowlist was correct; the scan also found four further
documentation lines added by the dep rows, all allowlisted with reasons rather than edited
(scope rule): `tests/fish/conftest.py:60`, `tests/fish/test_pane_isolation.py:19` (a fish
string run inside the throwaway home), `tests/hooks/test_ensure_rcs.py:30` and
`tests/lib/python/test_cc_worktree.py:440`. `lib/python` component: 481 passed, 1 xfailed.

## System Learnings

- `$HOME/dotfiles` inside a fish test under the runner names the throwaway link, not the
  live checkout, yet matches the pattern; the allowlist handles it.
- The `lib/python` component takes about 3 minutes; give it a long timeout.

## Process Improvements

- The brief's allowlist list went stale as dep rows landed docstrings; the stale-entry test
  now flags the reverse drift too.

## Self-Improvement Notes

- Small, well-specified row: doing it directly was faster than delegating.
