# Worklog: Implement vendor update, diff, and check commands

**Date**: 20260308-014716-MST
**Task**: m-002
**Agent**: w-02

## Summary

Implemented three vendor CLI subcommands on top of the m-001 scaffold:

- **`vendor update <name> [--ref <tag>] [--abort]`** — Fetches upstream, determines target ref (explicit tag, latest tag, or origin/HEAD), generates watch-pattern-filtered diff, writes `.review-pending` marker, checks out new ref, opens diff in $PAGER. `--abort` reverts to pinned commit.
- **`vendor diff <name> [--ref <tag>]`** — Read-only diff between pinned_commit and upstream, filtered by watch_patterns, output to stdout.
- **`vendor check [--quiet]`** — Fetches all deps, prints aligned table (NAME/PINNED/LATEST/BEHIND). `--quiet` suppresses output when up-to-date, prints + exits 1 when updates exist.

Also added 5 git helper functions to clone.go: `GitFetchTags`, `GitDiff`, `GitLatestTag`, `GitRevParse`, `GitCommitsBehind`.

## How It Went

Smooth. The m-001 scaffold was well-structured with clean abstractions (manifest, clone helpers, error helpers). The new commands integrated naturally. One refinement needed: the initial `check` implementation exited 1 in both quiet and normal mode when updates existed, and quiet mode printed nothing even when updates were found. Fixed to only exit 1 in quiet mode and to print the table in both modes when updates exist.

## System Learnings

- Shallow clones (`--depth 1` from `vendor add`) require `--unshallow` before diffs/rev-lists work. The `GitFetchTags` function handles this with a fallback.

## Process Improvements

None.

## Self-Improvement Notes

- Reviewed subagent output carefully and caught the exit-code behavior issue before committing. Good practice to always review generated code against spec requirements.
