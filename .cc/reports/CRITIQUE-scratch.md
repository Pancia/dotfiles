# Critique: `scratch`, auditable throwaway space for Claude

Date: 2026-11-16. Read-only review of `.cc/plans/PLAN-scratch.md`. Nothing was
built. It reuses the facts in `.cc/reports/CRITIQUE-toss.md` and does not
repeat them.

## Verdict

**Build it, with changes.** The shape is right. The user's new wants make a
persistent root and an automatic expirer necessary: files must outlive the
3-day cleaner, and every create and discard must go through a command we
control. So the main objection to `toss` (it moves files out of a place that
cleans itself, and needs a deleter) no longer applies. The other objections
still apply: the plan's path checks are too wide, the classifier result is
unknown, and the path details are missing.

The plan has five gaps that must close before it is built:

1. "Files you made" is only rule text. The tool refuses only `/`, `$HOME`,
   `~/Cloud` and its own `discard/`, so `scratch discard ~/projects` would
   succeed.
2. Its `~/Cloud` check cannot work as written (see problem 2).
3. It does not say whether the scratchpad or `scratch new` is the default home
   for throwaway files. If the scratchpad stays the default, the retention want
   is not met for most files.
4. Writes into a `scratch new` folder are outside every pre-approved directory.
5. The expirer goes live as soon as its plist exists, because
   `_ENSURE_SERVICES` installs it at the next fish start.

## 1. Does it meet each want?

| Want | Met? | Notes |
|---|---|---|
| Claude does not use `rm` | Yes, by rule | The rule is advisory. Nothing stops a bare `rm`. A `PreToolUse` Bash hook that warns on `rm`/`mktemp` would enforce it. It costs no tokens unless it fires. |
| `trash` is for the user's files | Yes | `discard` keeps throwaway files out of the 500-entry trash history. |
| Throwaway files go somewhere else | Partly | `discard` covers files that already exist. Open question 3 leaves new throwaway output in the scratchpad, which still expires after 3 idle days. |
| Auditable, through commands we control | Partly | It audits only what goes through `scratch`. A bare `mv`, `mktemp -d` or Write-tool file leaves no trace. Launchd runs have no session id. The log is plain text that Claude can edit unless the write permission is narrowed (see change 4). |
| Lasts longer than 3 idle days | Yes, for `scratch` paths | 14 days. But see "Retention vs disk". |

Over-built: very little. `MANIFEST.tsv` repeats the audit log, but it is the
only way to move a batch back by hand, so keep it. `scratch ls` must cap `du`.
No `restore` is right for now.

Under-built: the guards in problems 1 to 4, the expirer's own safety, and the
link to the "Where to put work files" section.

## 2. Problems, ranked

1. **Nothing enforces "files you made".** The deny-list is four paths.
   `~/projects`, `~/Library`, `~/dotfiles`, a repo root, `.git/` and
   `.cc/plans/` are all accepted. A glob such as `scratch discard *` in a
   project root moves the whole project. A mechanical check is possible: the
   path's birth time is after the Claude process started
   (`ps -o lstart= -p "$CLAUDE_PID"`). Tested caveat: setting a file's
   modification time to an earlier date also moves its birth time back
   (`touch -t`, `tar x`, `cp -p`, `rsync -t` do this). So the check refuses
   some real throwaway files. That failure is safe. A resumed session has a new
   process, so it refuses files made before the resume.
   - Birth time is a necessary condition, not proof. A file that the user or a
     peer session made after this Claude process started passes. Outside a jj
     repo, nothing else catches that case.
   - `CLAUDE_PID` is set by Claude Code itself; nothing in dotfiles sets it.
     I did not check that a `claude-p --safe-mode` run has it.
   - With `CLAUDECODE=1` and no `CLAUDE_PID`, refuse. In the user's own shell
     (no `CLAUDECODE`), skip this check: the user decides.
   - Exempt only this session's own scratchpad (its path holds the session id)
     and runs that this session created (the audit log records them). Do not
     exempt all of `/private/tmp/claude-$UID/` or all of `runs/`. Otherwise
     `scratch discard /private/tmp/claude-501/-Users-anthony-dotfiles` passes
     every guard and moves about 20 live sessions' scratchpads. Refuse `runs/`
     itself and any folder above a session folder.
   - Also cap the number of arguments (for example 20) unless `--many` is
     given.

2. **The `~/Cloud` refusal cannot work by prefix, and the device check does not
   catch it.** `~/Cloud` → `~/ProtonDrive` → `~/Library/CloudStorage/ProtonDrive-*`
   is three spellings for one folder. Its real path is on the same device as
   `~` and `/private/tmp` (16777233, checked with `stat -L`). So a `st_dev`
   test passes it, and a literal `~/Cloud` prefix misses the other two
   spellings. A move out of a File Provider folder is a delete in the cloud, and
   it syncs to every device. A cloud-only file may need a download first. The
   check must compare the real path of the parent with
   `~/Library/CloudStorage/` and `~/Library/Mobile Documents/`.

3. **A tracked file in a repo becomes a deletion the user must deal with.**
   Measured in a test jj repo: a committed file moved out shows `D
   committed.txt` in `jj st`. A new file (added in `@`, not in `@-`) moved out
   leaves no change. In this shared checkout, a tracked deletion is a Bash
   change. `commit-mine` stops with exit 5 and offers a `commit-mine --also`
   line. Following that line commits a deletion that the user never asked for.
   For a new file that Claude created with Write, the `drop_vanished` fix
   (`37fb347f`, `lib/python/ccjj.py`) already drops the stale record, so that
   case is safe. Rule:
   refuse a path that `@-` tracks (`jj file list -r @- -- PATH`) or that git
   tracks (`git ls-files --error-unmatch`). Say "this is a repo file: use
   `trash` and tell the user". Also, before discarding a file in a jj repo, ask
   `ccjj who PATH` (read-only). Refuse if another session has records on it,
   because the move would take that session's work in progress. I did not check
   the output or exit code of `ccjj who`, so this use is untested.

4. **No write permission for `scratch new` folders.** `additionalDirectories`
   holds only `~/.claude/plans`. Only the session scratchpad is pre-approved.
   So outside auto mode, each Write into `runs/…` asks for permission. In auto
   mode, the default "Local Operations" rule covers only "the repository the
   session started in"; it calls `~/` "scope escalation". Fix: add only
   `~/.local/share/claude-scratch/runs` to `additionalDirectories`. Do not add
   the root, so `discard/` and the audit log stay outside Write's reach. This is
   a permission change, so the user decides. The Bash sandbox is not set in
   `rcs/claude-settings.json`, so the `scratch` script itself can write its
   root without an extra entry.

5. **The expirer goes live too early, and it deletes.**
   - `_ENSURE_SERVICES` installs any new `services/*/*.plist` at the next fish
     start of any kind, `trash` included. Another session in this checkout can
     start it. Write the plist as `*.plist.disabled` until the tests pass.
   - Guards it needs:
     - The root is a real directory, not a symlink. The current user owns it.
       It holds a marker file such as `.claude-scratch-root`.
     - It deletes only direct children of `runs/` and `discard/` whose names
       match `^\d{8}-\d{6}-`.
     - It uses `shutil.rmtree`, which is symlink-safe here
       (`rmtree.avoids_symlink_attacks` is `True` on this session's Python).
       Launchd may run a different Python, so the script asserts this at
       startup and stops if it is false. It makes read-only folders writable
       on error.
     - It never crosses a device.
   - A run's age cannot come from its folder's mtime. Tested: appending to a
     file, or writing in a subfolder, leaves the top folder's mtime unchanged.
     Use the newest mtime found by a bounded walk, for example at most 10,000
     entries. If the walk reaches the limit, keep the run and log it.
   - `scratch expire` refuses to delete when `CLAUDECODE` is set. Only
     `--dry-run` works then. All deletes stay with launchd. This also keeps
     Claude away from the "Irreversible Deletion (general)" and "Auto-Mode
     Bypass" rules.
   - Write one audit line per batch deleted, with its size.

6. **The scratchpad and `scratch new` overlap with no rule between them.** The
   harness tells every agent to use the scratchpad, and "Where to put work
   files" says to keep throwaway test repos there. Those die after 3 idle days.
   My recommendation: `scratch new` is the home for throwaway files anyone
   might look at, such as test repos, repro output and test runs. The
   scratchpad keeps only raw command output that nobody will read. The "never
   cite a scratchpad path" line must also cover scratch paths, because they
   expire too.

7. **Path details not in the plan** (each one was tested or follows from the
   tests above):
   - **Strip trailing slashes first.** Tested: for `lnk/`, Python's `basename`
     is empty and `islink` is `False`, so the code acts on the link's target.
     After stripping, resolve the parent with `realpath`, `lstat` the last
     part, and move the link itself.
   - **Normalise `..` with the real parent.** Then compare with a trailing
     slash (`/a/b/` contains `/a/b/c`, but not `/a/bc`).
   - **Refuse these paths:**
     - the scratch root and any folder above it. A rename into its own
       subtree already fails with `EINVAL` (tested), but give a clear message.
     - `$PWD` and any folder above it.
     - any direct child of `$HOME`, and anything under `~/Library`.
   - **Refuse sockets, FIFOs and devices.** `/private/tmp` holds a live
     Postgres socket.
   - **Version control folders.** Refuse a folder that contains `.git` or
     `.jj` at its top level, and any path that has `.git` or `.jj` in it.
     Allow a folder with `.git` or `.jj` only in this session's scratchpad or
     a run this session created. Throwaway test repos are a real case there. Moving a git worktree away leaves a stale worktree entry.
   - **Cross-disk.** Use `os.rename` and refuse on `EXDEV`. Never let `mv`
     copy and then delete.
   - **Batch layout.** Put each item at `discard/<batch>/<n>-<basename>` so that
     `a/out` and `b/out` do not collide. Make the batch with `mkdtemp`. Append
     each item's line to `MANIFEST` after it moves, not before.
   - **Literal paths only.** A path that comes from command output is
     invisible to the classifier. Its "Unverifiable Deletion Target" rule
     fails closed on that shape for `rm -rf "$VAR"`, and it may do the same by
     analogy here.

8. **Audit log format and growth.**
   - Paths can hold tabs and newlines, so TSV can break. Use JSON Lines, and
     have `scratch log` print it as a table.
   - Fields: local ISO time with offset, actor, action, source, destination,
     batch, bytes, result and error, cwd.
     - actor is `claude`, `subagent`, `user` or `launchd`.
     - Session id: Claude Code exports `CLAUDE_CODE_SESSION_ID` and
       `CLAUDE_SESSION_ID`, with the same value. ccjj reads the second one.
     - Subagents share the parent's id. `CLAUDE_CODE_CHILD_SESSION=1` marks a
       subagent. `CLAUDE_PID` gives the process.
     - None of these exist in the user's own shell or under launchd.
   - Write each line with one `O_APPEND` `write()`.
   - Growth is small: about 300 bytes a line, so 500 actions a day is about
     4.5 MB a month. Use monthly files (`audit/2026-11.jsonl`), and let
     `expire` delete files older than 12 months.
   - It is not tamper-proof. `chflags uappnd` blocks an accidental `>`, but the
     owner can clear that flag. Say so in the docs, and do not claim more.

9. **Retention vs disk.** The disk is 89% full, with 24 GB free.
   `/private/tmp/claude-501` holds 462 MB after 30 hours of uptime. At that
   rate, 14 days is about 5 GB, or 20% of free space. A single discarded
   `node_modules` or `target/` folder can add several GB. Add a size cap
   (`SCRATCH_MAX_GB`, default 5): above it, `expire` deletes the oldest first.
   Add a free-space floor: below 10 GB free, the same applies. Neither may
   delete anything younger than 3 days. Without that floor, one 6 GB discard
   makes `expire` delete everything, today's batch included, which breaks the
   retention want. When the floor stops it, `expire` deletes nothing more. It
   logs the shortfall and sends one notification.
   Time Machine has no destination here, so backups are not a concern. The jj
   operation log still keeps the content of a discarded new file. That only
   matters for secrets, and those are never pushed unless committed.

10. **Name.** `scratch` is free. `command -v scratch` finds nothing. The only
   near match is `bin/akr-scratch`, which writes dated notes, so the names do
   not clash.

## 3. The global CLAUDE.md rule

- The plan's rule is 288 characters, about **70 tokens**, not 45 (estimate:
  characters ÷ 4). Every request in every session and subagent pays it as input.
- "Replaces File Deletion" is wrong as worded. That section is about 810
  characters (about 200 tokens) in three paragraphs. Paragraphs 2 (the `trash
  restore` pointer) and 3 (search for a name before a move, rename or delete)
  must stay. Replace only paragraph 1 (176 characters, about 44 tokens).
- "Write test scripts with the Write tool…" serves none of the stated wants.
  Decide it separately. Leaving it out saves about 20 tokens.
- It says "Never run `rm`" but does not say "yourself". Code under test can
  contain `rm`, as the vote script did. It also does not name `mktemp -d`, which
  the user asked for, or forbid `scratch expire`.

Suggested paragraph 1 (270 characters, measured with `wc -c`; about 68 tokens,
so about +24 net):

> Never run `rm` yourself; code under test may. Make throwaway folders with
> `scratch new`, never `mktemp -d`. Clear throwaway files you made with
> `scratch discard`, using literal paths. Anything else: `trash`; if it fails,
> ask me. Never run `scratch expire`; launchd does.

Change in "Where to put work files" (the new bullet is 219 characters against
about 150 now, plus one word in the "never cites" line; about +20 tokens):

- The scratchpad bullet becomes: "**In a `scratch new` folder:** throwaway files
  anyone might look at, such as test repos and repro output. They last 14 days.
  **In the scratchpad:** only raw command output. It is cleared at reboot and
  after 3 idle days."
- "A plan or report never cites a scratchpad or `/private/tmp` path" becomes
  "…a scratchpad, `scratch` or `/private/tmp` path".

Total: about +45 tokens of input on every request.

## 4. Will auto mode allow `scratch discard` where it blocked `rm`?

What is known (rule text from `claude auto-mode defaults`, version 2.1.326;
the session that hit the block ran 2.1.325):

- No default rule names a move to a new path. "Irreversible Local Destruction"
  lists `mv` only "onto an existing untracked or out-of-repo path", that is, an
  overwrite. A `discard` destination is always new. The other deletion rules
  ("Irreversible Deletion (general)", "Unverifiable Deletion Target", "Shared
  Scratch Sweep") are written about deleting, and a move can be undone. The
  classifier may still treat a move into an expiring folder as a delayed
  delete; the rule text does not settle that.
- But `scratch` is an unknown command. The classifier sees only its name and
  arguments. It does not see that `discard` is a move into a folder that
  expires.
- The destination is outside the project, and "Local Operations" calls `~/`
  scope escalation.
- "Auto-Mode Bypass" (ii) blocks "taking a denial in bad faith and tunneling the
  same action through a different path". A `scratch discard` of the same target
  right after an `rm` denial fits that shape.
- `scratch expire`, run by Claude, would be an age-filtered recursive delete.
  That is why it must refuse under `CLAUDECODE`.

What the user can add (their edit, not Claude's): put `scratch` in the
`autoMode.environment` personal-tools line in `rcs/claude-settings.json`, next
to `trash`. Add one sentence: it moves files into an expiring folder and never
deletes.

What stays unknown: the classifier is a model, not a rule engine, so the rule
text does not predict a given call. The cause of the earlier block is still
unproven (see the toss critique). A trial in an auto-mode session tells us
something, but it guarantees nothing. Try `scratch discard <literal path>` on
files made in that session, several times and in a few shapes, and log each
result.

## 5. Concrete changes to the plan

1. Add the guards in problems 1, 2, 3 and 7: birth time after the session
   started, real-path checks for cloud folders, refusal of tracked files and
   peer-held files, a cap on the argument count, and the path rules.
2. Decide open question 3 as in problem 6, and edit "Where to put work files" to
   match.
3. Replace only paragraph 1 of "File Deletion". Use the text in section 3.
4. Propose (user's decision): `additionalDirectories` += the scratch root's
   `runs/` only; `scratch` in the autoMode personal-tools line.
5. Expirer: develop as `.plist.disabled`. Add the guards in problem 5, the size
   cap and the free-space floor. It runs daily at 04:00, after `disk-snapshot`
   (03:00) and `cc-transcript-backup` (03:30).
6. Audit: JSON Lines, monthly files, the fields in problem 8.
7. Tests: `tests/bin/scratch/test_scratch.py`, which drives the script as a
   subprocess, as `cc-peers` is tested. Use `SCRATCH_ROOT`, a fake `$HOME` and
   a fake `CLAUDE_PID` start time, all under `tmp_path`. Register `"bin/scratch"`
   in `COMPONENTS` with an alias, and add a row to `docs/testing.md`. (Note:
   `tests/bin/cc-peers/` is still not registered.) Cover every refusal in
   problems 1 to 3 and 7, `EXDEV` (fake it), the expirer on a planted symlink
   and on a read-only tree, and `expire` refusing under `CLAUDECODE`.
8. Docs: a row in the Quick Reference and the services table of
   `~/dotfiles/CLAUDE.md`, and a short page next to
   `docs/claude-global/trash.md`.

## 6. Revised spec

Root: `${SCRATCH_ROOT:-~/.local/share/claude-scratch}`. It holds `runs/`,
`discard/`, `audit/` and a marker file. Python, in `bin/scratch`.

- `scratch new [LABEL]`: `mkdtemp` makes
  `runs/<YYYYMMDD-HHMMSS>-<label>-XXXX/`. It prints the path and logs it.
- `scratch discard [--many] PATH...`: moves each path with `os.rename` into
  `discard/<YYYYMMDD-HHMMSS>-XXXX/<n>-<basename>`. It appends a line to the
  batch `MANIFEST` and to the audit log after each move.
  - It refuses, and moves nothing, on any of these:
    - a cross-device path (`EXDEV`)
    - a real path under `~/Library/CloudStorage/` or
      `~/Library/Mobile Documents/`, or anything else under `~/Library`
    - `/`, `$HOME`, a direct child of `$HOME`, `$PWD` or a folder above it,
      the scratch root or a folder above it, or anything inside `discard/` or
      `audit/`
    - a socket, FIFO or device
    - `runs/` itself, `/private/tmp/claude-$UID/` or any folder above a
      session folder
    - a folder with `.git` or `.jj` in it, or a path through one, unless it is
      in this session's scratchpad or a run this session created
    - a file that jj `@-` or git tracks
    - a path another live session has ccjj records on
    - under `CLAUDECODE`: a path born before `$CLAUDE_PID` started, or no
      `CLAUDE_PID` at all (this session's scratchpad and runs are exempt)
    - more than 20 paths without `--many`
  - It strips trailing slashes. It moves a symlink, not its target.
- `scratch ls`: batches and runs, newest first, with age and size. `du` stops
  after 5 seconds.
- `scratch log [N]`: the last N audit entries as a table.
- `scratch expire [--dry-run]`: deletes runs and batches older than
  `SCRATCH_KEEP_DAYS` (14). A run's age is its newest mtime from a bounded
  walk. Above `SCRATCH_MAX_GB` (5), or below 10 GB free, it deletes the oldest
  first, but never anything younger than 3 days; if that is not enough, it logs
  the shortfall and notifies once. It refuses to delete when `CLAUDECODE` is
  set, and stops if `rmtree` is not symlink-safe. It deletes audit months older than 12. It is run daily
  by `services/scratch-expire/`.
- Not included: `restore` (move a batch back with `MANIFEST`), a deleting mode
  for Claude, and any change to the system's `/tmp` cleaner.
