# Worklog: Fix image-wall: change .stationary to .moveToActiveSpace and rebuild binary

**Date**: 20260310-171907-MDT
**Task**: m-012
**Agent**: w-12

## Summary

Changed `collectionBehavior` in `cmd/image-wall/main.swift` line 84 from `[.stationary, .ignoresCycle]` to `[.moveToActiveSpace, .ignoresCycle]`. Rebuilt the binary with `swiftc -o bin/image-wall cmd/image-wall/main.swift -framework AppKit`. Build succeeded cleanly.

## How It Went

Straightforward one-line change. No complications. No test/lint targets exist in this repo (dotfiles project), but the Swift compiler validated the code successfully.

## System Learnings

None — simple targeted fix.

## Process Improvements

None.

## Self-Improvement Notes

None.
