# PLAN: `scratch`, auditable throwaway space for Claude

Status: built and on 2026-11-16 (bin/scratch, services/scratch-expire daily 4:30). Retention 14 days, 5 GB. Replaces the `toss` idea
(`.cc/reports/CRITIQUE-toss.md`) and the `discard` idea that followed it.

## Problem

- Claude must not run `rm`. Auto mode may block it, and the user wants no
  deletes they cannot see.
- `trash` is for the user's own files. Its history holds 500 entries, and
  throwaway files push real ones out.
- `/private/tmp` (the session scratchpad) is cleared at reboot, and daily at
  00:00 by `com.apple.tmp_cleaner`: it deletes any file whose access,
  modify and change times are all more than 3 days old. That is too short
  for a spot check, and cannot be changed without editing a system file.
- Throwaway files are not always in a temporary folder: a test file in a
  project, a debug copy in `.cc/misc/`, build output beside the code.
- The user wants every create, move and delete of throwaway space to be
  auditable, through commands we control: no bare `mktemp -d`, `mv` or `rm`.

## Proposal

One command, `bin/scratch`, with a root outside `/tmp`:
`~/.local/share/claude-scratch/` (same disk as `/private/tmp`: a move is a
rename).

- `scratch new [LABEL]`: create `runs/<YYYYMMDD-HHMMSS>-<label>-<rand>/` and
  print its path. Replaces `mktemp -d`.
- `scratch discard PATH...`: move the paths into
  `discard/<YYYYMMDD-HHMMSS>-<rand>/`, keeping each one's original path in a
  `MANIFEST.tsv` inside the batch. Refuses a path on another disk (a move
  would be a copy; use `trash`), a path inside the scratch root's own
  `discard/`, `/`, `$HOME` itself, and any path under `~/Cloud`.
- `scratch ls`: recent runs and discard batches, with size, age and the first
  few paths.
- `scratch log [N]`: the audit log.
- `scratch expire [--dry-run]`: delete runs and batches older than
  `SCRATCH_KEEP_DAYS` (default 14). The only command that deletes. Run daily
  by a launchd service (`services/scratch-expire/`).
- Every subcommand appends one line per action to
  `~/.local/share/claude-scratch/audit.log`: local time, action, session id
  (when Claude Code exports one), cwd, path, size.

## Global CLAUDE.md rule (replaces "File Deletion")

```
Never run `rm` yourself. A throwaway folder: `scratch new`. Throwaway files
you made, wherever they are: `scratch discard`. Anything you did not make, or
are unsure about: `trash`; if it fails, ask. Write test scripts with the
Write tool and run `sh FILE`, not `sh -c "$(cat FILE)"`.
```

About 45 input tokens per request.

## Changes from the critique (`.cc/reports/CRITIQUE-scratch.md`)

- `discard` refuses: files tracked by git or jj (a move shows as a deletion
  that `commit-mine` would then commit); a folder that holds a repo root;
  anything whose real path is under `~/Library/CloudStorage/` (all three
  spellings of `~/Cloud` resolve there); `/`, `$HOME`, the scratch root; any
  other session's scratchpad under `/private/tmp/claude-<uid>/`. It cannot
  prove "a file you made": the audit log is the check, not the tool.
- Each run and batch records its creation time in a `META.json`; expiry reads
  that, never folder mtimes (appends do not change them).
- `expire` refuses to run when `CLAUDECODE` is set, so only launchd or the
  user deletes. A size cap (default 5 GB) may delete early, but never
  anything younger than 3 days.
- The expire service is developed as `*.plist.disabled`, so
  `_ENSURE_SERVICES` does not install it before it is tested.
- Audit log: JSON Lines, one file per month
  (`audit/YYYY-MM.jsonl`), with `CLAUDE_CODE_SESSION_ID` when set.
- The CLAUDE.md rule replaces only the first paragraph of "File Deletion";
  the `trash restore` pointer and the search-before-rename paragraphs stay.
  "Where to put work files" is edited to match. Net cost: about 45 input
  tokens per request.
- Two settings changes are the user's call: `runs/` in
  `additionalDirectories` (so writes there need no approval), and `scratch`
  in the auto-mode personal-tools line.

## Open questions

- Retention: 14 days against a disk at 89% full.
- Whether `scratch` needs an auto-mode settings entry, as `trash` has.
- Whether the session scratchpad itself should stay the default for quick
  throwaway output, with `scratch new` only for things worth a spot check.
- Tests: `tests/bin/scratch/`, registered in `COMPONENTS`.
