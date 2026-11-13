# Review: Claude session storage, ccs and backups (2026-11-12)

**Status (same day):** findings 1-7 fixed, and the nightly ProtonDrive copy
(`services/cc-transcript-backup`) added. `cleanupPeriodDays` stays at 365 by choice, since
the ProtonDrive copy never deletes. Not fixed: test isolation of the stray scratchpad entries,
and the unlocked `sessions.json` writers. Paths longer than 200 characters get a hashed folder
name from Claude Code, which the restore fallback does not reproduce.

## Where chats live today

| Copy | Size / count | Off this Mac? |
|---|---|---|
| `~/.claude/projects/**.jsonl` (Claude Code's own transcripts) | 3.4 GB, ~1,020 interactive chats with content | No |
| `~/.local/state/claude-sessions/transcripts/*.zst` (ccs-title-hook copies) | 93 MB, 238 sessions | No |
| `~/Cloud/cc-sessions/**/session-backups/*.zst` (manual `ccsave`) | 67 sessions | Yes (ProtonDrive) |
| AKR `claude-chats/` markdown | 13 | Yes, with the vault |

- No Time Machine destination is configured. No restic or other job covers `~/.claude`.
- So about 950 chats exist only on the Mac's internal disk (90% full, SMART verified).
- `cleanupPeriodDays: 365` makes Claude Code delete transcripts older than a year. The
  oldest transcript is from 2026-01-08, so deletion starts around 2027-01-08.

## Code findings (ranked)

1. **Ctrl-Z deletes the entry of a live session.** `fish/functions/my-claude-code-wrapper.fish:153,236`.
   fish continues the function when claude stops, so finalize runs. After `fg` the session has
   no entry, no title and no backup. Tested in a pty.
2. **ccsave-hook overwrites `.cwd`.** `bin/ccsave-hook` (the `.cwd = $cwd` filter).
   `_ccs_open_register` stores the parent repo key (`ccs.fish:720`) and the scan matches it
   exactly. Worktree sessions, and `/clear` or `/resume` after a cd into a subfolder, vanish
   from `ccs list` at the root, and the wrapper's exit review and backup are skipped.
3. **Only wrapper sessions are backed up.** `bin/ccs-title-hook:17-18,31-32,50`. Plain `claude`,
   the desktop app and IDE sessions get no copy. A session with no title also gets no copy.
   Example: ffe43022 (2026-11-09, 134 turns) has no entry and no backup.
4. **`ccs resume` archives before it knows the resume works.** `ccs.fish:1144-1149`.
   `_ccs_restore_transcript` gives up when `transcript_path` is empty (`ccs.fish:676-678`), even
   when a backup exists. 16 open entries are in that state. `ccs old` cannot resume.
5. **The last 10 minutes are never backed up.** `bin/ccs-title-hook:78-88`. No final, unthrottled
   copy on exit, `/clear` or `/resume`.
6. **A claude crash under a live wrapper counts as a clean exit.** The wrapper ignores `$status`
   and finalize deletes the entry.
7. **`ccsave` uses the wrong folder.** `bin/ccsave:15,34-37`. It keys on the current folder, not
   the launch key, and builds the transcript path with `tr '/' '-'` only, so a path with a dot
   gets no Cloud backup.

Minor: a fish test writes entries into the real `open/` folder (no `XDG_STATE_HOME` isolation);
`sessions.json` is rewritten by two writers with no lock.

Checked and fine: restore never overwrites a live transcript; `ccs prune` only archives;
`--continue` and `--fork-session` stamp normally.

Fixed earlier today (e74d355a): the entry did not follow an in-session `/resume`. Most open
entries with no transcript and no backup (Aug-Nov) are that bug.

## Recommended order

1. Raise `cleanupPeriodDays` (not to 0: 0 disables transcripts).
2. A nightly service that copies changed transcripts, zstd-compressed, off the Mac. This
   covers findings 3 and 5 for every session, wrapper or not.
3. Move finalize and a last backup into a `SessionEnd` hook (findings 1, 5, 6).
4. Keep the registered key in `.cwd`; store the hook's cwd in a new field (finding 2).
5. Archive only after the transcript is in place; derive the path when it is empty (finding 4).
6. Fix `ccsave` paths (finding 7) and the test isolation.
