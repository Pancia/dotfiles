# Critique: `toss`, a mover for throwaway files

Date: 2026-11-16. Read-only review of a proposal; nothing was built.

## Verdict

**Do not build `toss` as proposed.** It moves throwaway files out of a place
that cleans itself (`/private/tmp`) into one that does not (`~/.cache`), and
then needs a deleting `prune` that someone must remember to run. The real
problem is smaller: Claude deletes test output only to reset a test, and a new
folder per run removes that need. A rule change in the existing "File
Deletion" section does the job for about 40 more input tokens per request and
no new code.

If a named mover is still wanted, build the small version in the revised spec
below: it moves inside `/private/tmp/claude-<uid>/`, so it needs no `prune`.

## What the evidence says

- **Cause of the block is unverified.** The rejected call has no classifier
  reason in the transcript; its record says only "User rejected tool use". Two
  earlier calls in the same session ran `rm -rf "$H"` (with `H` set in the same
  call) and `sh -c "$(cat …)"` without any block. The rejected call differed
  in three ways: it used a second session id's scratchpad (one conversation
  used two session ids' scratchpads; I did not find why), it ran two scripts
  generated at runtime through `$(cat …)`, and it forked 30 background
  subshells. Any of these could explain the prompt. So nobody can claim that a
  `toss` call would have passed where that call did not. The rules cited here
  come from `claude auto-mode defaults` on version 2.1.326; the rejected call
  ran on 2.1.325.
- **`/private/tmp` already cleans itself.** Every entry under
  `/private/tmp/claude-501/` is newer than the last boot (2026-11-15 09:42).
  macOS also runs `com.apple.tmp_cleaner`, a daily job at 00:00 (loaded; one
  run since boot, exit 0). The script `/usr/libexec/tmp_cleaner` does
  `cd /tmp`, which follows the symlink into `/private/tmp`, then deletes
  files whose atime, mtime and ctime are all older than 3 days, and empty
  folders older than 3 days. `/etc/periodic` does not exist on this system.
  Today `/private/tmp` holds 465 MB after about 30 hours of uptime.
- **Plain `mktemp -d` does not land in the scratchpad.** Here it makes a folder
  under `$TMPDIR` (`/var/folders/…/T/`), which neither cleaner above covers.
  A rule must give the template form with the scratchpad as prefix.
- **Same volume.** `/private/tmp`, `~/.cache` and `~` are all on
  `/dev/disk3s5` (device 16777233), so a move between them is an atomic
  rename. The disk is 88% full, with 26 GB free.
- **`trash` is a poor home for throwaway files.** Its history
  (`~/.cache/dotfiles/trash/history`) is at its 500-entry cap, and at least 65
  of those 500 entries are scratchpad or `/tmp` paths. Each throwaway `trash`
  pushes one of the user's own entries out of `trash list` and `trash
  restore`. A shell here cannot list `~/.Trash` ("Operation not permitted"), so
  Claude cannot measure the "under 1 GB" limit directly; it can only sum the
  items named in the history.

## Problems, ranked

1. **It inverts the cleanup direction.** Files in the scratchpad vanish at
   reboot and after 3 idle days. Files tossed to `~/.cache/toss/` stay until
   someone runs `prune`. With no automatic pruner, disk use only grows, on a
   disk that is 88% full. With a launchd pruner, it is an automatic deleter in
   `~/.cache`, which is what the user wanted to avoid, plus a plist, a script
   and tests to maintain.
2. **`prune` is the same problem again.** It is an age-filtered recursive
   delete of files that existed before the session. If Claude runs it, auto
   mode's default "Irreversible Deletion (general)" rule applies, and "Shared
   Scratch Sweep" (age-filtered deletes in a cache directory) could apply.
   Running it right after an `rm` was
   blocked also fits the "Auto-Mode Bypass" rule ("tunneling the same action
   through a different path"). The design already keeps `prune` with the user;
   that must stay true.
3. **The allowed roots are too wide.** `/tmp` and `/private/tmp` are shared.
   Today they hold a live Postgres socket (`/private/tmp/.s.PGSQL.5432`) and
   about 20 other Claude sessions' scratchpads for this repo alone. A move
   breaks a socket or another session's files as surely as a delete. A glob
   such as `toss /tmp/*` would move all of it, and the script cannot tell a
   glob from a list. One conversation also used two session ids'
   scratchpads, so "the current scratchpad" is not one fixed path.
4. **The classifier may not treat `toss` as safe.** No default rule blocks a
   move to a new path, and a move is reversible. But the classifier sees only
   the name and arguments of an unknown command. The autoMode environment in
   `rcs/claude-settings.json` lists `trash` among the user's personal tools;
   `toss` is not there. Adding it is an edit to auto-mode settings, which is
   the user's decision, not Claude's.
5. **"Run test scripts from a file" does not fix what it targets.** The
   classifier does not see command output. A script written to a file at
   runtime (as `vote.sh` was, extracted by `node`) is just as hidden when run
   as `sh FILE` as when run as `sh -c "$(cat FILE)"`. What helps is a script
   whose text appears in the transcript, that is, one written with the Write
   tool: the default rules tell the classifier to look back at earlier Edit
   and Write calls, and they say command output never reaches it.
6. **The rule contradicts the current text.** "File Deletion" still says "If
   `trash` fails, try `rm` as a fallback". A new "Never run `rm`" line beside it
   gives two orders. Also, the script under test (the vote script) itself
   contains `rm -f` for its own temp file. The rule must say Claude's own
   commands, not the code under test.
7. **Smaller gaps if it is built anyway.**
   - Path checks must resolve the parent with `realpath` but not follow the
     last component (move the symlink, as `trash` does), compare with a
     trailing slash (`/private/tmp/claude-501x` is not inside
     `/private/tmp/claude-501`), and refuse the roots themselves, `.`, `..`
     and the scratchpad root.
   - It must refuse a cross-device move rather than let `mv` fall back to
     copy-then-delete, which can leave half a tree in each place. Check
     `st_dev`, or use `os.rename` and fail on `EXDEV`.
   - Two arguments with the same base name (`a/out`, `b/out`) collide inside
     one batch. Keep relative paths or number them.
   - Two calls in the same second collide on a time-stamped batch name. Use
     `mkdtemp` (time stamp plus random suffix).
   - A process still writing a moved file keeps writing to it in its new place;
     a running process whose working directory moved keeps running there.
     Neither is an error, but `toss ls` sizes can grow after the move.
   - `du` on a large tree is slow. `toss ls` should cap the time or the depth.
   - A deleter must handle read-only folders (for example a Go module cache
     or `.git/objects`): `chmod -R u+w` first, or the delete fails halfway.

## Simpler paths, compared

| Option | Deletes? | New code | Cleans up by itself | Notes |
|---|---|---|---|---|
| New `mktemp -d "$SCRATCHPAD/run.XXXX"` folder per test run, leave old ones | No | None | Yes (boot, daily cleaner) | Removes the need to delete. Recommended. |
| `mv` into `$SCRATCHPAD/discard/<new name>` | No | None | Yes | Use when a test needs a fixed path to be free. The destination must be new each time: the default rules count `mv` onto an existing path as destructive. |
| `trash` while under 1 GB | No | None | No (Trash is never emptied automatically: `FXRemoveOldTrashItems` is unset) | Evicts the user's restore history; size cannot be listed. |
| `toss` into `~/.cache/toss/` | `prune` does | Script, tests, maybe a service | No | The proposal. |
| `toss` into `/private/tmp/claude-<uid>/toss/` | No | Small script, tests | Yes | Revised spec below, if a named tool is wanted. |

## Conventions any new script must follow

- Name: `toss` is free. `command -v toss` finds nothing, and a whole-word
  search of `~/dotfiles` and `~/.config` finds no use. The global "before you
  move, rename or delete" check applies to renames and deletions, not to a new
  name, but run it again if the name changes.
- Language: `bin/` mixes Python and shell. `bin/cc-peers` (Python, tested by
  driving it as a subprocess with fixtures under `tmp_path`) is the closest
  model. A fish script would need `/fish` first and would put its tests in the
  slow `fish` component.
- Tests: `tests/bin/toss/test_toss.py`, run with `cmds test toss`. Register
  `"bin/toss"` in `COMPONENTS` in `lib/python/run_tests.py` with an alias, and
  add a row to `docs/testing.md`. Without the registry entry the tests never
  run in a full `cmds test`. That trap already exists: `tests/bin/cc-peers/`
  has tests but no `COMPONENTS` entry.
- Tests must never touch the real `/private/tmp/claude-*` or `~/.cache`. Give
  the roots as environment overrides (for example `TOSS_ROOT`,
  `TOSS_ALLOWED`) and point them at `tmp_path`.
- Docs: a row in the Quick Reference table of `~/dotfiles/CLAUDE.md`, and a
  short note next to `docs/claude-global/trash.md`.

## The CLAUDE.md rule

Token figures below are estimates (characters divided by four), not
measurements.

- The proposed rule is 120 characters, about 30 tokens. It is input on every
  request in every session, subagents included, because the global CLAUDE.md
  loads everywhere.
- Adding it as a new line leaves the contradiction in problem 6. The cheaper
  and clearer form rewrites the existing "Prefer `trash` over `rm`…" line
  (about 165 characters) in place. Suggested text (about 330 characters, so
  about 40 tokens more than today):

  > Never run `rm` yourself. Use `trash` for the user's files; if it fails, ask
  > me. Leave throwaway files in the scratchpad; macOS clears it at reboot and
  > after 3 idle days. Start each test run in a new folder,
  > `mktemp -d "<scratchpad>/run.XXXX"`, instead of deleting the old one.
  > Write a test script with Write, then run `sh FILE`; never
  > `sh -c "$(cat FILE)"`.

- "yourself" keeps the rule off product code that contains `rm`. The
  `mktemp -d` clause removes the main reason Claude deletes at all. The
  scratchpad prefix matters: a bare `mktemp -d` lands in `$TMPDIR`.
- If `toss` is built, replace "Throwaway files stay in the scratchpad…" with
  "Move throwaway files out of the way with `toss`", and add `toss` to the
  autoMode personal-tools line (user's decision).

## Revised spec (only if a named tool is still wanted)

`toss PATH...`
- Moves each path into a new batch folder made with `mkdtemp` under
  `/private/tmp/claude-$UID/toss/`. Same volume, so each move is a rename.
  The system's own cleanup removes batches; there is no `prune`.
- Accepts a path only if its real parent is inside
  `/private/tmp/claude-$UID/<project>/<session>/` (one level below a session
  folder or deeper) and the path is owned by `$UID`. Refuses the scratchpad
  root, the roots above it, `.`, `..`, and anything else, with a pointer to
  `trash`.
- Does not follow a final symlink. Refuses a cross-device move instead of
  copying. Keeps each argument's path relative to its scratchpad, so two
  `out` folders do not collide.
- Prints one line per move: source, then destination.

`toss ls`
- Lists batches, newest first: time, size (with a time limit on `du`), and the
  first three source paths.

Not included: `prune`, a launchd service, a history file, restore. A batch
can be moved back with `mv` while it exists.
