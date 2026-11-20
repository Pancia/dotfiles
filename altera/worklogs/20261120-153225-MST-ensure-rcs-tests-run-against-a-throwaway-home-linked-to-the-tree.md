# Worklog: ensure-rcs tests run against a throwaway home linked to the tree

**Date**: 20261120-153225-MST
**Task**: m-018
**Agent**: w-32

## Summary

Row HOOKS (R6). Only `tests/hooks/test_ensure_rcs.py` changed.

- New `tree_home` fixture: a `tmp_path` home with `dotfiles -> DOTFILES` and a
  plain file at each destination the tests name (`.config/tmux/tmux.conf`,
  `.config/fish/config.fish`, `.claude/CLAUDE.md`, `.claude/hooks/ensure-rcs.sh`,
  `Library/LaunchAgents/org.pancia.vpc.plist`). Plain files, not hardlinks, so the
  tree is never written.
- `run_hook(mode, path, home)` and `run_hook_raw(mode, payload, home)` now
  require a home and always pass it as `HOME`. The old `run_hook_home` was the
  same thing, so it is folded into `run_hook`. `test_allows_empty_file_path` and
  `TestPerformance` go through them too.
- Every `Path.home()` is gone; `TestJsonParsing.DST` is now a `dst` fixture.
- Assertions that looked for `"dotfiles/rcs/tmux.conf"` and
  `"dotfiles/services/vpc/..."` now look for `DOTFILES.resolve() / ...`: the hook
  resolves `~/dotfiles` before naming the source, so under a worktree or a
  scratch checkout the path does not end in `dotfiles`.
- R6.2: `TestPreMode::test_reads_the_manifest_of_the_tree_under_test` parses the
  first non-comment MANIFEST entry, creates its destination in the fixture home,
  and asserts exit 2, "via rcs/MANIFEST", and the tree's source path in stderr.

Result: `uv run lib/python/run_tests.py hooks -v` → 114 passed (4 failed before:
three TestPreMode cases and the we"ird-symlink case). `test_cc_worktree_nudge.py`
already passed under isolation; no change needed (R10.3).

## How It Went

Straightforward. The four failures had two causes: the isolating runner's HOME
has no destination files (so `realpath` fails and the symlink test resolves
nothing), and the source path in messages is the resolved tree path.

## System Learnings

- `claude-ensure-rcs-hook.sh` names sources by `realpath "$HOME/dotfiles"`, so
  any test string match on a source path must use the resolved tree path.
- The hook's pre mode never runs `bin/rcs-sync`, and post mode only for paths
  under `dotfiles/rcs/` or service plists, so the performance tests (post mode on
  an unrelated `/tmp` path) are safe against the real tree.

## Process Improvements

None.

## Self-Improvement Notes

Ran the component once before editing to see the real failures under isolation;
that pinned both causes before changing anything.
