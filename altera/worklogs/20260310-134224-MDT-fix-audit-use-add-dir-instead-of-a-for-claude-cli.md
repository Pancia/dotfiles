# Worklog: Fix audit: use --add-dir instead of -a for claude CLI

**Date**: 20260310-134224-MDT
**Task**: m-007
**Agent**: w-07

## Summary

One-line fix in `cmd/vendor/audit.go` line 370: changed `"-a"` to `"--add-dir"` when passing the vendor directory to the claude CLI. The `-a` flag doesn't exist; `--add-dir` is the correct flag. Rebuilt the binary with `go build`.

## How It Went

Straightforward. Read the file, made the edit, rebuilt, verified with `go vet`.

## System Learnings

None - simple bug fix.

## Process Improvements

None.

## Self-Improvement Notes

None.
