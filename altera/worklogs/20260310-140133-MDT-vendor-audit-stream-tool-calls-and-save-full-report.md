# Worklog: Vendor audit: stream tool calls and save full report

**Date**: 20260310-140133-MDT
**Task**: m-009
**Agent**: w-09

## Summary

Modified `runClaudeReview` in `cmd/vendor/audit.go` to use `--output-format stream-json --verbose` and parse JSONL output line-by-line. Tool call summaries (Read, Grep, Glob, Bash) are shown in real-time on stderr and captured in an `auditReview` struct. The full report now includes an "Investigation" section listing all tool calls before the AI assessment text.

Key changes:
- Replaced `bytes`/`io` imports with `encoding/json`
- Added JSON structs for stream event parsing (`streamEvent`, `streamMessage`, `contentBlock`)
- Added `auditReview` struct to carry both tool call log and final text
- Added `formatToolCall` helper for human-readable tool call summaries
- Rewrote `runClaudeReview` to pipe stdout through `bufio.Scanner` and parse JSONL
- Uses `env -u CLAUDECODE` to work inside Claude Code sessions
- Updated `runClaudeDiffAudit`, `cmdAudit`, and `buildReport` signatures accordingly

## How It Went

Straightforward implementation. The task spec was very detailed with exact code to use, making it a clean apply. Build and vet pass cleanly.

## System Learnings

None.

## Process Improvements

None.

## Self-Improvement Notes

None.
