# Review: the `scratch` build

Date: 2026-11-16. Read-only review of the uncommitted `bin/scratch`,
`services/scratch-expire/`, `tests/bin/scratch/test_scratch.py`, the
`run_tests.py` entry, the two settings lines, and the CLAUDE.md text. It
checks them against section 6 of `.cc/reports/CRITIQUE-scratch.md`.

`cmds test scratch`: 32 passed. Every probe below ran against a fake `HOME` and
`SCRATCH_ROOT`. Repos that had to be outside the session scratchpad were in a
`mktemp -d` folder under `$TMPDIR`, written as `$W` below. The real
`~/.local/share/claude-scratch` was not touched. Each finding says whether it
was **reproduced** or found **by inspection**.

A trap for anyone who checks these results: any path under
`/private/tmp/claude-<uid>/<project>/<session>/scratchpad/` is exempt from every
repo and birth-time check (finding 7). A repo test made in a scratchpad
therefore "passes" for the wrong reason. My first jj probe did exactly that.

## Verdict

The shape matches the spec. The move-only design, the refusal list, the batch
layout, JSON Lines audit, the expirer's containment check and the 3-day floor
are all in place. But three problems make the guards weaker than they look:

1. Every guard compares path **strings**, and APFS has several spellings for
   one file.
2. `expire` acts on a size and age walk that it knows is incomplete.
3. The birth-time test passes any file that was saved by atomic replace
   during the session.

Fix 1 and 2 before the plist is enabled. Fix 3, or at least reword the
refusal, before relying on the rule in auto mode.

## High

### 1. A different spelling of a path gets past every guard (reproduced)

`bin/scratch:272-312`, `223-237`. `check()` makes `loc` from
`realpath(parent) / name`, and then compares it as a string with `home`,
`home/Library`, `cwd`, the scratch root, `rr/"discard"`, `rr/"audit"` and
`/private/tmp/claude-<uid>`. `realpath` resolves symlinks, but it keeps the
letter case as typed. It also does not undo the `/System/Volumes/Data`
firmlink prefix. The volume is case-insensitive, so each guard has other
spellings that reach the same folder.

Reproduced (user shell; inside Claude, the birth-time check is the only other
guard):

- `scratch discard $HOME/library/CloudStorage/P/doc` moved a folder out of
  `~/Library/CloudStorage`. On the real disk that is a delete in the cloud.
- `cwd=$HOME/work/deep/deeper; scratch discard $HOME/work/DEEP` moved a folder
  above the current folder.
- `scratch discard $HOME/.local/share/CLAUDE-SCRATCH/audit` moved the whole
  audit folder into a discard batch. `scratch log` then showed one entry, and
  the old history would expire in 14 days. This defeats the audit.
- `scratch discard /System/Volumes/Data$HOME/kid` moved a direct child of
  `$HOME`. It is the same inode as `$HOME/kid`.
- **The git and jj tracked check too:** `scratch discard $W/r3/PLAIN` moved the
  git-tracked `plain` (`git status` shows `D plain`). `scratch discard
  $W/jr/PLAIN` did the same in a jj repo. `git ls-files -- PLAIN` and
  `root:"PLAIN"` are case-sensitive, so neither finds the file.
- By inspection: `/private/TMP/claude-501/...` is outside `scratchpad_zone`.
  Unicode normalization (NFC or NFD) gives yet more spellings.

Inside a Claude session, a tracked file that Claude edited this session also
passes the birth-time check (finding 3). So the case form of its name moves it
with no `--old`.

Fix: canonicalize before any comparison. `fcntl.F_GETPATH` on an fd opened on
the real parent returns the on-disk case, with the firmlink removed. Tested:
`/USERS/ANTHONY/DOTFILES/BIN` gives `/Users/anthony/dotfiles/bin`, and
`/System/Volumes/Data/private/var/...` gives `/private/var/...`. For the last
part, open it with `O_SYMLINK` (so a link is not followed) and call
`F_GETPATH`, or find its entry in `os.listdir(parent)`. Pass that on-disk name
to git and jj. A stronger option for the protected folders: compare
`(st_dev, st_ino)` of each of `loc`'s ancestors with home, `~/Library`, the
scratch root, `discard/`, `audit/` and the cwd chain. Add tests for case and
firmlink spellings.

### 2. `expire` deletes from a walk it knows is incomplete (reproduced)

`bin/scratch:384-407` (`items`), `459-488`. `items()` gives all runs and
batches one shared 5-second walk budget. When the budget runs out, `walk()`
returns only the top folder's own size and mtime, with `whole=False`.
`cmd_expire` ignores `whole`.

- For a run, `ref = max(created, newest)`. With a cut-short walk, `newest` is
  the top folder's mtime. Writing in a subfolder, or appending to a file,
  does not change that mtime (the critique measured this). A run made 20 days
  ago and still in use today is then judged 20 days old and deleted.
  Reproduced by running the real `items()` and `cmd_expire --dry-run` with a
  clock that jumps: `would delete (age, 20.0d, 128B)` for a run with a file
  written today in `sub/`. The same run shows age `0.0` with a full walk.
- Sizes are undercounted, so the size cap triggers too rarely. Space-rule
  ordering uses the same wrong `ref`.
- How likely: `os.walk`+`lstat` here ran at about 9,150 entries per second
  (measured on `~/dotfiles`, 44k entries in 4.8 s). So about 45k entries use up
  the whole budget. One discarded `node_modules` is often bigger. Every item
  listed after it, in `iterdir` order, is then judged on its top folder only.
- The spec said: "If the walk reaches the limit, keep the run and log it."

Fix: give each item its own budget, or a larger budget for `expire` only. Do
not delete by age or space any item with `whole=False`. Write
`expire-skipped` with `note="walk incomplete"` for it. Add a test that patches
the deadline.

### 3. Birth time passes any file saved by atomic replace (reproduced)

`bin/scratch:321-325`. I made `pre.txt`, then started the stand-in "session"
process, then ran `os.replace(tmp, "pre.txt")`, as the Edit tool and many
editors save. `scratch discard pre.txt` then succeeded with no `--old`: the
replacement has a new birth time. So "made this session" really means "written
by rename since the session started". That covers any untracked file Claude
edited (a `.env`, an untracked note, a file under `~/.config` outside any
repo), and any file the user saved in such an editor during the session.

The other caveats from the critique still hold, and two make this worse:

- A subagent gets the **parent's** `CLAUDE_PID`. I checked it in this session:
  the start time was 7.5 hours before this subagent began. So everything
  written in those hours passes.
- The refusal text says `pass --old if you made it` (line 325), and `pass --old
  if you are sure` (line 323). In auto mode, the model reads that and retries
  with `--old`. The guard is then one retry deep. The CLAUDE.md rule never
  mentions `--old`.

Fix: you cannot repair birth time itself. These changes make it cheaper to be
wrong:

- Reword the refusals to "not made in this session: use `trash`, or ask the
  user". Keep `--old` as a flag for the user, and do not name it in the
  message.
- Also refuse when `st_ino` existed before the session. That is not knowable
  either, so a better route is to log each Write and Edit path per session
  (ccjj already journals jj repos) and accept only those paths outside jj.
- At least say in the CLAUDE.md rule that `--old` is for the user only.

## Medium

### 4. A path through `.git` or `.jj` is not refused (reproduced; spec deviation)

`bin/scratch:310`. The build refuses only a folder that *contains* `.git` or
`.jj`. The spec also refuses "a path through one".

- User shell: `scratch discard $W/r1/.git` moved the `.git` folder. `scratch
  discard $W/jr/.jj` moved `.jj`. `git ls-files -- .git` and the jj fileset
  return nothing, so both looked "untracked".
- Claude mode: after the stand-in session started, I ran `git branch newbranch`.
  `scratch discard $W/r2/.git/refs/heads/newbranch` then succeeded, and the
  branch was gone. Git and jj write fresh files all the time, such as refs,
  `index.lock`, op heads and working-copy state. All of them pass birth time.

Fix: refuse when any part of `loc` relative to the repo root is `.git` or
`.jj`, except inside a scratchpad or run.

### 5. A read-only subtree turns into a zombie with a false audit line (reproduced)

`bin/scratch:498-499`. `shutil.rmtree(p, ignore_errors=True)` cannot delete
inside a folder with no write bit, such as the Go module cache or a
`chmod -R a-w` fixture. The code still writes `expire` with the full byte
count and prints `deleted`.

- Reproduced: a run of 20 days with `mod/pkg@v1/a.go` under `chmod -R a-w`.
  After `expire`, `mod/` is still there, but `.scratch-meta.json` is gone. So
  the next `items()` takes the run's top folder mtime, which is now. The run
  looks new, so it is kept 14 more days. Then it fails and is logged again,
  for ever.
- The spec said to make read-only folders writable on error and test it. That
  was not done.

Fix: use `onerror=` (Python 3.9 under launchd has no `onexc=`) to
`chmod u+w` the failing path's parent and retry. `lstat` it first, and skip a
symlink. Afterwards, check
`p.exists()`. Write `expire-failed` in place of `expire` if it still exists.
Add the test.

### 6. Git pathspec magic hides a tracked file (reproduced)

`bin/scratch:227`. `git ls-files -- REL` reads REL as a pathspec. A tracked
file named `:junk` is checked as `junk`. Git found nothing, and
`scratch discard $W/r3/:junk` moved it (`D :junk`).

The glob form did **not** hold: the tracked `a[1].txt` was correctly refused,
because git also matches the literal name.

Fix: run `git --literal-pathspecs ls-files -z -- REL`, or set
`GIT_LITERAL_PATHSPECS=1`.

### 7. The exemptions are wider than the spec (by inspection; spec deviation)

`bin/scratch:256-266`, `307`. The spec exempts "this session's scratchpad"
and "a run this session created". The build exempts:

- the contents of **any** session's scratchpad, in any project
  (`parts[2] == "scratchpad"`, with no session id check);
- the contents of **any** run.

The exemption skips the repo, tracked-file, peer and birth-time checks. So
Claude can discard the files of another live session that are in use.
Recovery is possible for 14 days, but the other session breaks now.

Fix: for the scratchpad, require `parts[1] == session()`. Subagents share the
id, so they still pass. For a run, require its `.scratch-meta.json` `session`
to equal `session()`, or `--old`. Also make the `/private/tmp/claude-<uid>`
base overridable by an env var, so the tests can reach it (finding 10).

### 8. The free-space rule makes `expire` noisy and over-eager (reproduced)

`bin/scratch:478-508`.

- With `SCRATCH_MIN_FREE_GB` above the real free space and a root holding
  287 bytes, `expire --dry-run` printed `still 287B kept and 20.5G free after
  expiry; nothing older than 3 days is left to delete`. With `--notify`, launchd
  sends that every day for as long as the disk stays low. The cause is
  outside the scratch root, so the message points at the wrong thing. The spec
  says "notifies once".
- While the disk is low for any reason, every daily run deletes every run and
  batch older than 3 days. The spec allows this, but it means the 14-day
  promise in CLAUDE.md fails silently on a disk that is 89% full. The disk had
  21 GB free during this review.

Fix: report a shortfall only when `total > max_bytes`, or when deleting the
whole root could not reach `min_free`, and say "the disk is low; scratch holds
only X". Notify at most once per condition, for example with a stamp file
under the root. Write the low-disk deletes with `reason="disk"`, apart from
`"space"`.

### 9. One expire test depends on the host's free disk (reproduced)

`tests/bin/scratch/test_scratch.py:315-327`. `Env.run` copies
`os.environ` minus `CLAUDE*` and `SCRATCH_ROOT`, so `SCRATCH_MIN_FREE_GB`,
`SCRATCH_MAX_GB` and `SCRATCH_KEEP_DAYS` leak in. The disk's real free space
also counts. `SCRATCH_MIN_FREE_GB=100000 cmds test scratch -k size_cap` fails
on `assert "still" not in r.stderr`. That is what a machine with under 10 GB
free will see.

Fix: in `Env.run`, drop every `SCRATCH_*` variable, and set
`SCRATCH_MIN_FREE_GB=0` unless a test sets it.

### 10. The tests miss several claims (by inspection)

- `test_refuses_places_that_are_never_throwaway` (lines 119-133): `home-child`
  and `cwd-parent` are the same path (`e.work`). The home-child check comes
  first (line 286), so the "folder above the cwd" rule is never reached for a
  real ancestor. The test asserts only `returncode != 0`, so a traceback or
  the wrong refusal also passes. Assert the reason text, and use a
  grandparent of the cwd for `cwd-parent`.
- Not tested at all:
  - `scratchpad_zone`: the `/private/tmp/claude-<uid>` base is hard-coded,
    and pytest's `tmp_path` is outside it;
  - the device check (`EXDEV`);
  - `held_by_peer`;
  - the refusal of `discard/` and `audit/` contents;
  - a trailing slash on a symlink (the exact case in the critique);
  - `..`;
  - `expire` on a planted symlink and on a read-only tree (both asked for in
    the critique);
  - audit-month pruning;
  - `--notify`.
- `docs/testing.md` has no row for `bin/scratch`, and there is no doc page
  next to `docs/claude-global/trash.md`. Section 5, items 7 and 8, asked for
  both.

## Low

### 11. `..` is collapsed before symlinks are resolved (reproduced)

`bin/scratch:273`. `os.path.abspath` collapses `b/link/..` to `b` as text. The
kernel goes through `link` first. With `b/link -> a/sub`, `scratch discard
b/link/../x` moved `b/x`, but `mv b/link/../x` would act on `a/x`. Each guard
still runs on what is moved, so this is not a safety bypass. But it moves a
different file than the one named. The spec says "normalise `..` with the real
parent". Fix: refuse any argument with a `..` part, or resolve the parent with
`realpath` before collapsing.

### 12. "Moves nothing" fails on errors at move time (reproduced)

`bin/scratch:350-378`. The duplicate check (`loc in locs`) and the
parent-and-child check (`b in a.parents`) compare strings. So `scratch discard
$W/d1 $W/D1/sub/f` passed both checks. It moved `d1`, failed on `D1/sub/f`
with `ENOENT`, and exited 1 with a partial batch. A mount point as the target
(`EBUSY`), or a name of 250 or more characters (the `N-` prefix pushes it past
255), also fails part-way. The audit log records each part. Finding 1's
canonicalization fixes the case form. For the others, check the target's own
`st_dev` against its parent's, and check the name length, before any move.

### 13. The peer check is weak (reproduced in part)

`bin/scratch:240-253`.

- `ccjj who bin` reported "no session has journal records…" for a folder that
  holds files with live records. So a folder is never "held".
- A live peer with only a Bash window is ignored.
- A timeout or error returns False, so the check fails open.

All three let a peer's new, uncommitted work be moved. It can be recovered.
Fix: for a folder, run `ccjj who` on each file in it, or add a prefix mode to
ccjj. Treat any `live` line as held, and treat an error as held.

### 14. `expire` and the marker are easy to get past (by inspection)

- `bin/scratch:461`: the in-session gate tests only `CLAUDECODE`.
  `env -u CLAUDECODE scratch expire` gets past it, which is the
  "tunnelling" shape the auto-mode rules forbid. Also test `CLAUDE_PID` or
  `CLAUDE_CODE_SESSION_ID`, or walk the parent processes for `claude`.
- `bin/scratch:115-122`, `466`: any `new` or `discard` writes the marker. So
  the marker proves only that `scratch` has run there before, not that the
  folder is a scratch root. The name check that the spec asked for
  (`^\d{8}-\d{6}-`) is missing. Containment still limits deletes to
  `<root>/runs/*` and `<root>/discard/*`. So this matters only if
  `SCRATCH_ROOT` points at a folder that already has a real `runs/`. Add the
  name pattern.

### 15. Output and log details (reproduced or by inspection)

- `scratch log 0` prints the whole log, because `lines[-0:]` is every line
  (line 442). Treat 0 as "none", or reject it.
- A name with a newline prints raw in `ls`, `log` and the refusal messages, so
  it can fake a line on screen. The JSON stays correct. Print with `repr()`,
  or replace control characters.
- `cmd_ls` catches `ValueError` and `KeyError` but not `TypeError`, so a
  MANIFEST line that is valid JSON but not an object crashes it. This needs a
  damaged file, so it is low.

### 16. CLAUDE.md and settings text (by inspection)

- `rcs/claude-user-claude.md:160`: the paragraph is 473 characters, about 118
  tokens, against 176 before. That is about +74 tokens on every request. The
  critique's text was 270 characters. The plan's "+45 tokens" is too low.
- Line 160 keeps "Write test scripts with the Write tool and run `sh FILE`".
  The critique said to decide that separately, and it adds about 20 tokens.
  It does not say "using literal paths", and does not say that `--old` is for
  the user (see finding 3).
- Line 160 says "Only the daily `scratch expire` job deletes", and lines
  205-207 say "kept 14 days". The rule is already live: `~/.claude/CLAUDE.md`
  is the same inode. But the plist is `.disabled`, so nothing deletes now.
  The root grows until the job is enabled.
- Lines 209-212: "never cites a scratchpad or `/private/tmp` path" was not
  extended to `scratch` paths, which also expire. The critique asked for this.
- `rcs/claude-settings.json:306`: "moves throwaway files into an audited
  holding area instead of deleting them" leaves out that the area is deleted
  after 14 days. A classifier that later learns this may count it as a
  misleading claim. Suggest: "…into an audited holding area that a daily job
  empties after 14 days; it never deletes by itself".
- `rcs/claude-settings.json:85` (`additionalDirectories` += `runs`) matches
  the spec.

## Suspicions that did not hold up

- **A trailing slash on a symlink:** `scratch discard lnk/` moved the link,
  and the target and its contents stayed. A symlink in the parent is resolved:
  `~/Cloud/doc` is refused (suite test).
- **jj fileset quoting:** a tracked file named `we"ird\name` was correctly
  refused. A colocated repo is checked as jj, because `.jj` is tested before
  `.git` at each level. A repo reached through a symlinked path was found and
  refused.
- **Timeouts and errors** from git or jj return None, which is a refusal (line
  316). A merge `@-` with two parents also errors, which is also a refusal.
- **Containment in expire:** with `runs/` replaced by a symlink to a folder
  that holds a 2025 project, `expire` deleted nothing. It logged
  `expire-skipped … outside the scratch root`. Symlinked run folders are
  skipped by `items()`.
- **Launchd's Python:** with launchd's default `PATH`, `python3` is
  `/usr/bin/python3` 3.9.6. `rmtree.avoids_symlink_attacks` is True there.
  `new`, `ls`, `log` and `expire` all ran under it. The wrapper and plist match
  `cc-transcript-backup` except the hour, and `plutil -lint` passes.
- **Audit-month cutoff:** it keeps the current month and the 12 before it.
  Leap years do not shift the month.
- **Audit concurrency:** each record is one `write()` on an `O_APPEND` file,
  even above 8 KB, because CPython passes large writes straight through. The
  month name and the timestamp come from two `now()` calls. That only matters
  at midnight on the last day of a month.
- **Time zones and resolution in the birth-time check:** `ps lstart` and
  `time.mktime` both use local time. The DST fall-back hour can shift the
  start by an hour, but only for a session that started in that hour.
  Truncating to whole seconds lets in only a file made less than a second
  before the session.
- **Non-UTF-8 names**, which would break the JSON writes after a move: APFS
  refuses such names. I did not test this.

## Deviations from the revised spec (section 6)

| Spec | Build | Matters? |
|---|---|---|
| Exempt only this session's scratchpad and its own runs | Any scratchpad, any run | Yes (finding 7) |
| Refuse a path through `.git`/`.jj` | Only a folder containing one | Yes (finding 4) |
| Keep and log a run when the walk hits its limit | Deletes on partial data | Yes (finding 2) |
| Make read-only folders writable; test it | Neither | Yes (finding 5) |
| Notify once on a shortfall | Every daily run | Some (finding 8) |
| Children of `runs/`, `discard/` match `^\d{8}-\d{6}-` | No name check | Little (finding 14) |
| Root is a real dir owned by the user | Marker only; realpath containment | Little: containment holds |
| `MANIFEST` | `MANIFEST.jsonl` | No, it is better |
| 04:00 | 04:30 | No |
| Added: `--old`, `SCRATCH_MIN_FREE_GB`, `--notify` | — | `--old` wording matters (finding 3) |
| `docs/testing.md` row, doc page next to `trash.md` | Missing | Low |
