# Session-scoped jj commits (`ccjj` / `commit-mine`)

> **Is this the right tool?** This is the answer for a repo that **cannot be
> isolated** — `~/dotfiles`, where about half the tracked files load by absolute
> path so a second checkout can author changes it cannot run. For any other repo,
> give each session its own working copy instead:
> **[docs/cc-worktree.md](cc-worktree.md)**. The two compose — see "Inside a
> worktree" below.

## Setup

**Nothing to run.** The hooks are registered in `rcs/claude-settings.json` and
the routing decides for itself, so `commit-mine` and the nudge work as soon as a
second session appears.

One optional extra, once per checkout, if you want changes made through `Bash`
(`sed -i`, `>`, a heredoc) to be recoverable rather than merely reported:

```bash
ccjj bash-windows on        # already on in ~/dotfiles
```

See "Bash windows" below for what that buys and what it deliberately does not.

## The problem

Several Claude Code sessions can share one jj working copy. jj snapshots the
**entire** working copy on every command, so a plain `jj commit` in one session
captures whatever the others have half-written — including files they created.
Path arguments (`jj commit <path>`) only help when the sessions touch disjoint
files; they cannot split a file two sessions both edited.

jj's own answer to concurrency is one working copy per worker (`jj workspace`).
That was investigated for this repo and rejected: ~46% of tracked files load by
absolute path from `/Users/anthony/dotfiles` (all 35 `rcs/MANIFEST` entries are
hardlinks, `~/.config/fish/functions` is a symlink into the main checkout, `PATH`
and `PYTHONPATH` and Hammerspoon's `package.path` are all pinned), so a second
checkout can author changes it cannot run. The working copy has to stay shared.

## The mechanism

1. A `PostToolUse` hook on `Edit|Write` (`ccjj record-edit`) journals one record
   per edit: the path, the `old_string`/`new_string` pair, and
   `tool_response.originalFile` — the file's full content immediately before that
   edit.
2. `commit-mine -m MSG` takes each journaled path **as it exists in the parent
   commit `@-`**, replays only this session's recorded edits onto it, and hands
   the result to `jj commit --tool=<generated script> <paths>`.

A jj "diff editor" receives `$left` (before) and `$right` (after) as directories
and takes whatever is left in `$right` as the selected content. Nothing requires
it to be interactive, so a generated script is a valid diff editor. Because
selected + remaining equals the original, **jj writes nothing back to the working
copy** — the other session never sees its work disappear.

Attribution is exact rather than heuristic: the other session's edits are absent
by construction, never filtered out.

## Usage

```bash
commit-mine -m "message"                       # the normal case
commit-mine --diff                             # preview, commit nothing
commit-mine -m "msg" --also old.txt --also new.txt   # a Bash-made rename
ccjj audit                                     # changes no session claims
ccjj prune -n                                  # what retention would remove
```

Session identity comes from `$CLAUDE_SESSION_ID`, which Claude Code sets for the
agent's own Bash calls, so the normal invocation takes no session argument.
**Subagents share the parent's session id**, so `Task`-spawned work is included.

Exit codes: `0` ok · `1` refused · `2` nothing to do or not in a jj repo · `4`
locked, base moved, or the working copy is a merge (retry) · `5` this session has
unclaimed Bash-window paths.

Two cases are deliberately **not** `4`, because they are not retryable: a payload
that jj would not select (`the commit did not take`) exits `1`, since re-running
reproduces it exactly; and an empty commit exits `2`. `--also` paths are taken
wholesale and are reported on their own line as **unverified**, because they never
pass through the byte check.

## Known limitations

**The Bash blind spot** — see "Bash windows" below. The `record-edit` hook sees
only `Edit` and `Write`, so anything done through `Bash` is journaled nowhere.
Deletions and renames are declared with `--also`; content changes are *offered*
by `ccjj claim` in an opted-in checkout, and otherwise commit nothing. `ccjj
audit` is what makes that loud instead of silent.

`--also` is safe only for whole-path operations (add / delete / rename), because
there is no hunk ambiguity in a whole-file change. Using it on a content-modified
file that another session also touched would take the working copy wholesale and
swallow their edits.

**`claude-p` disables hooks.** `bin/claude-p:104` adds `--safe-mode` by default,
which turns hooks off — a headless agent spawned that way produces **no journal
at all**, so every change it makes is unclaimed. Set `CLAUDE_P_SAFE=0` when the
work must be attributable.

**Files over 1 MiB are invisible.** `snapshot.max-new-file-size` defaults to
`1MiB`; jj warns and skips them.

**Mode changes** are taken from `@-` for paths that already exist there, so
another session's `chmod` cannot leak into your commit — but your own `chmod` on
an existing file is not committed either.

## Why each guard exists

Every one of these was reproduced against a working prototype, and every one
failed *silently*. They are tested in `tests/lib/python/test_ccjj.py`.

| Guard | What it holds back |
|---|---|
| Exclusive `flock` across read→commit | Two concurrent `jj commit` runs create a **divergent change**: both print success, both exit 0, one commit lands on a dangling head and the colocated git HEAD goes inconsistent. |
| Pin `@-`, re-verify before committing | The lock excludes other `ccjj` runs, but a bare `jj` from an agent's Bash still moves `@-`. Committing a payload built against a stale parent **reverts** whatever landed in between. |
| Post-commit byte verification, then rollback | `jj commit --tool` accepts `$right` **only** for paths that already differ between `@-` and the working copy. For any other path it discards the payload, makes an empty commit, and reports success — and the journal would then be consumed, making the work unattributable. This check is mandatory, not a nicety. |
| Context anchoring | `Edit` guarantees `old_string` is unique in the file it was applied to, not in `@-`. Plain first-occurrence replacement patched the wrong site whenever `@-` held the old text twice. A line-based 3-way merge is not the fix either: it produces a **false** conflict when two sessions edit adjacent lines. |
| `replace_all` count check | The agent asked for every occurrence *it could see*. A different count in `@-` means committing would change lines nobody looked at. |
| Bytes end to end | Text mode decoded CRLF away and rewrote whole files; non-UTF-8 content raised an uncaught `UnicodeDecodeError` that blocked every path in the journal. |
| `cwd=root` and quoted `root-file:` patterns | jj filesets resolve against the CWD, so running from a subdirectory matched nothing; and jj's default fileset pattern is a **glob**, so a filename containing `~ & \| ( ) [ ]` was parsed as an expression. |
| Out-of-repo path detection | An edit to a file outside the repo produced a `../` fileset whose base read failed, which was then reported as a nonexistent conflict — locking the session out permanently. |
| `jj op restore` when the commit itself fails | A failed `jj commit` is not a no-op. A `jj util snapshot` racing it — which `~/.claude/hooks/jj-snapshot.sh` runs on **every `Edit` in every session**, and which our lock does not exclude — returns rc 0 instantly while the commit dies rc 255 with `Concurrent checkout`, leaving the commit on a dangling head and two **divergent** changes. Reproduced 3/3. The old code `die()`d before any rollback. |
| Refuse an empty commit | The byte check below only notices failure when the payload *differs* from `@-`, so a reconstruction that coincidentally equals `@-` verified clean, banked an empty commit under your message, and consumed the journal. `jj log -T empty` is asked directly instead. |
| `commit_id ++ "\n"` in `parent_id()` | On a **merge** working copy `jj log -T commit_id -r @-` exits **0** and concatenates both parents into one 80-char string, so the `"more than one revision"` guard — gated on `returncode != 0` — never fired and `pinned` became nonsense. |
| `os.path.islink` before the payload copy | jj materializes a tracked symlink in `$right` as a **real symlink** and `shutil.copyfile` follows it, writing through to the target — possibly outside the repo (`bin/hermes-native` points into `~/projects/hermes`). It must be `islink`, not `lexists`: for a regular file `copyfile` writes *in place*, and that is the only thing carrying the exec bit for a path not yet in `@-`. |
| `parent_ids()` at module scope | The bare-`commit_id`-on-a-merge bug was the *same defect in three places*. Fixing it only in `cmd_commit` left `survey()` reporting **"nothing unclaimed"** on a merge working copy (audit going blind exactly when the repo is most confusing, and disagreeing with `commit`, which refused), and left `stamp_base()` writing an 80-char `.base` — written **once**, so that session reported phantom drift forever and `drift_undo()` could never match it. |
| Refuse a `Write` with no base over existing content | `original is None` means "the path did not exist when this change began". Taking the payload wholesale **reverted a commit another session had landed in between** — exit 0, verification passing. Worse, the diff `claim` prints was against `b""`, so the reader was never shown the content about to be destroyed: the offer model's own safety net misfiring. |
| `other_live_sessions` uses `has_activity` | A `.json`-only test made a peer doing **only Bash work** invisible — the likeliest peer in an opted-in contended checkout. Its work was claimable with no warning, and `should-scope` said "not contended" while `nudge` was announcing the opposite, so `g run ci` did a whole-copy commit that swallowed it. |
| `retire()` uniquifies with a counter | Committing twice in a day from one session is the **normal** pattern, and the archive path silently did nothing the second time. The third commit then replayed already-committed records, jj selected nothing, and the mandatory verification failed blaming the working copy — wedged until disowned. |
| The empty-commit check fails **closed** | `== "true"` alone meant any failure of that one `jj` call reopened the hole the guard exists to close. |
| `rollback()` reports its own failure | Three sites printed "rolled back … the journal is intact" without checking. The commit-failure site is reached precisely when the repo is already bad, which is when a restore is most likely to fail — and a false reassurance there is worse than no message. |
| The nudge only ever **sets** `ccjj-contended` | `others` is relative to the prompting session, so clearing made two sessions fight: the established one deleted the marker because the new peer had no journal yet, and the peer could not record a window to get one until the marker existed. Windows silently stopped. Clearing belongs where the whole picture is known (`retire-all`). |
| `ccjj audit` backs off while the lockdir is held | `survey()` snapshots, and a snapshot inside another session's `jj commit --tool` kills it — while the nudge tells every agent to run `ccjj audit`. |
| `.last` written via `os.replace`, length-validated | Subagents share the session id and run concurrently. A torn read gives a short prefix jj may resolve ambiguously, and since `window_span` always starts at the first window, one bad first window locks the session out of `claim` for good. |
| `already_applied()` before replaying an edit | A record is **not** retired when something outside ccjj commits its path, so the next commit replays it. Where `old` is a *substring* of `new` — extending an identifier, the commonest edit shape — the replacement re-fires on its own output and commits text that existed **nowhere**: `g2 -> g2-S` applied twice gives `g2-S-S`, exit 0, "committed and verified". The byte check cannot catch it: it verifies transcription of the payload, not that the payload corresponds to anything real. |
| `--also` validates the path and checks live sessions | `--also` is CWD-relative by design, but nothing checked the path existed — a run from a subdirectory invented `sub/oldname.txt` and reported it "committed and verified", and a typo in one half of a rename committed the **delete with no add**. It also took a path wholesale while a live session was mid-edit, with no warning, in exactly the situation `claim` refuses by name. |
| `surrogateescape` on **encode**, not just decode | A non-UTF-8 file arrives from the hook payload as lone surrogates, and `v.encode()` raised `UnicodeEncodeError` — blocking every *other* path in the journal too. |
| One journal file per record, `O_EXCL` | `>>` is atomic only per `write()` syscall; concurrent hooks scrambled record order and a 64 KB `Write` produced unparseable JSON. Records now carry their own pre-edit content, so ordering is no longer load-bearing either. |

## Routing: you should not have to remember

`ai_jj_commit` (and therefore `g run ci`) asks `ccjj should-scope` before doing
anything. If another **live** session is working here, it routes to `ccjj commit`
automatically; otherwise it commits the whole working copy as before. `/cc:commit`
carries the same instruction.

The rule is deliberately "only when someone else is here". With a single session
a whole-working-copy commit is *better*, because it also captures Bash-made
changes this tool cannot see. When it does route, `ccjj commit` reports any paths
no session claimed, so scoping never silently drops work.

Two details that matter:

- The message is generated from the **reconstructed** diff (`ccjj commit --diff`),
  not `jj diff`. For a file two sessions both touched, `jj diff` carries the other
  session's hunks, so the message would describe work that is not being committed.
- The routing decision happens **before** `ai_jj_commit` takes its lock, because
  `ccjj` now takes that same lockdir — delegating while holding it would make the
  tool deadlock against itself and return 4.

A deliberate whole-working-copy commit calls `ccjj retire-all`: every session's
claims are in history at that point, and leaving the journals live would make
their paths look permanently claimed and wedge the nudge on.

**One shared lock.** `ccjj` takes `~/.local/state/ai-jj-commit/<repo_key>.lock` —
ai_jj_commit's lockdir, in its `pid lstart` format, with its staleness rule — so
either tool can see and clear the other's. They previously used different locks
and did not exclude each other, and a `g run ci` racing a session commit is
exactly the divergent-change failure the inner flock exists to prevent. Release
is via `atexit`, since every `die()` and the `--diff` early return are exit paths
too and a leaked lockdir wedges both tools for 30 minutes.

## Bash windows: an offer, never an attribution

A `PostToolUse` hook on `Bash` (`ccjj bash-window`) records the pair of
working-copy commit ids either side of each Bash tool call. That pair is the
entire storage scheme: a rewritten working-copy commit stays readable and
diffable **by id** (verified across 10 further snapshots, 3 commits, `jj
abandon`, `jj undo` and `jj op restore`).

```bash
ccjj bash-windows on          # opt this checkout in
ccjj audit                    # unclaimed paths, annotated with what covers them
ccjj claim path/to/file       # accept one, after reading the diff it prints
ccjj claim path -n            # preview only
```

A claim writes an ordinary `Write`-shaped journal record, so everything
downstream is the existing `merge3` path and `commit-mine` stays exact **by
construction**.

**Why it is an offer.** A window's delta is a whole-working-copy diff, so it
contains every write that landed inside it — not just this session's. This was
reproduced against the real tool: session 2 makes a plain `Edit` inside session
1's window, session 1 commits session 2's change under its own message and
**exits 0**, and the mandatory byte verification *passes*, because it checks
fidelity of transcription, not provenance. With an insertion-shaped `Edit` — the
commonest shape — it is silent on both sides.

And other Claude sessions are not the only writers here. **103 tracked files are
hardlinked outside this repo**, including `rcs/claude-settings.json` (rewritten
from *any* project on `/permissions`) and `rcs/karabiner.json`; and
`~/.config/fish/functions` is a symlink into the checkout, so `fisher update` or
`funcsave` from any terminal writes straight into it.

No local rule can separate those from the agent's own work. Printing the diff and
requiring an explicit `claim` puts the one detector that does work — a reader —
in the loop.

### What `claim` refuses

| Case | Why |
|---|---|
| symlink, directory | `jj file show` exits **0 with empty stdout** for both, so claiming would write a zero-byte regular file over it — and the byte verification would compare `b""` to `b""` and pass. Checked at the span *and* re-checked at the narrowed endpoints, which can differ. |
| a path this session also `Edit`ed | The claimed blob already contains those edits; replaying both applies them twice, which for an insertion-shaped edit **duplicates a hunk silently**. |
| a path a live session claims — by an `Edit` record **or a Bash window of its own** | Its bytes are in your window. `--force` after reading the diff. |
| a path that did not exist when the window opened, but does in `@-` | Another session committed it in between; taking the window wholesale would revert them, and the diff shown would not mention it. |
| delete, rename | Whole-path changes have no hunks to split; routed to `--also`. |

Claimed content is stored **base64**, because it comes off disk rather than out
of a JSON tool payload and need not be UTF-8. `merge3` short-circuits when the
committed file equals the base — exact by definition, and the only reason binary
works at all, since `git merge-file` refuses binary outright (rc 255) and that
was previously reported as a content conflict.

### One commit, not two

`ccjj commit` **stops** (exit `5`) when this session has Bash-window paths nobody
has claimed, naming the exact `ccjj claim` lines. Claim what is yours, re-run,
and everything lands in one commit. `--no-claim` proceeds without them.

Surfacing alone was not enough, and shipping it that way was a mistake worth
recording: `ai_jj_commit` runs preflight → message → commit in a single
invocation, so an agent read the advisory note only *after* the commit had
landed, and the best it could then do was a second commit. Stopping is what makes
"claim it and re-run" a true statement.

The escape hatch is a plain CLI flag, which is why blocking is acceptable here
when it was not for the rejected `PreToolUse` guard: hooks do not inherit the
agent's environment, so that design had no way out and contention would have
become permanent. `--no-claim` is on argv, and the refusal names it.

**Humans never see this.** The session-scoped path only runs when
`CLAUDE_SESSION_ID` is set, so a human's `g run ci` takes the whole working copy
— which captures Bash-made changes anyway, and has nothing to claim.

### Cost, and the gates

`bin/ccjj-bash-window` is a shell pre-gate on the `jj-snapshot.sh` pattern: it
decides in two `test -f` and ~3 ms, without starting Python (~130 ms).

1. `.jj/ccjj-bash` — untracked, per-checkout opt-in.
2. `.jj/ccjj-contended` — maintained by `ccjj nudge`, which already computes
   liveness on every `UserPromptSubmit`.

Gate 2 is the important one: with a single session there is nothing to
attribute, so the snapshot is pure waste during the ~78% of active minutes that
are uncontended. When it does run, it is **one** `jj log -T commit_id -r @`,
which snapshots *and* returns the id in one process — 20 ms idle, 70 ms with a
pending change on a 4000-file repo. (Never add `--ignore-working-copy`: that
reports "No snapshot needed" and does nothing, with real changes on disk.)

Three consequences, all deliberate:

- Changes made **before** a second session appears are never covered.
- The **first** Bash call of a session only establishes a baseline.
- A window is skipped while the shared lockdir is held, because a snapshot
  landing inside `jj commit --tool` kills it with `Concurrent checkout` and
  leaves the repo divergent (reproduced 3/3).

`PostToolUse` only, deliberately: a paired pre/post would double the cost and
leak an open window whenever Post does not fire — which it often does not for a
failing Bash command. With a rolling marker a missing Post merely widens the next
window, so orphaned windows are not a category.

## The nudge

A `UserPromptSubmit` hook (`ccjj nudge`) injects one line into the agent's context
when another **live** session has a journal for the repo you are standing in:

```
[ccjj] Another Claude session is working in dotfiles. Commit with
`commit-mine -m "msg"` -- a plain `jj commit` captures their unfinished
work too. `ccjj audit` shows what nobody has claimed.
```

It exists because you type "commit stuff", not `/cc:commit` — the steer has to
arrive without you invoking anything. It deliberately does **not** look at what
you typed; gating on repo state instead of phrasing means there is no wording to
slip past. It makes zero `jj` calls (~66 ms, mostly interpreter startup), because
it runs on every prompt in every project.

It is deliberately *not* a `PreToolUse` block. That design was tried and rejected:
hooks do not inherit the agent's shell environment, so an env-var escape hatch
cannot work (verified — the hook sees it UNSET); a command-pattern list misses
`jj new`, `jj ci` (a built-in jj alias) and `git commit`; contention becomes
permanent, so it would block ordinary commits within days; and hooks fail *open*
on timeout, so a stalled guard permits rather than denies.

## Liveness and drift

Each session journal carries two stamps, written once:

- **`.owner`** — the owning `claude` process id plus its start time (`$CLAUDE_PID`
  is inherited by hooks). pid alone is not enough; pids are recycled. This is the
  same identity check as `ccs.fish:812` and `ai_jj_commit.fish:70-92`.
- **`.base`** — the `@-` the session started from.

A session counts as **live** only if its owner is still running *and* its journal
was touched within 12 hours. Both halves are needed: `/clear` and compaction
rotate the session id inside the *same* process, so a pre-`/clear` journal keeps a
live owner pid forever and would otherwise claim its paths indefinitely.

Only a live session's claim suppresses a warning. A dead session's paths are
exactly what you want to hear about — nobody is going to commit them.

`.base` exists because comparing the working copy against the *current* `@-` is
not sufficient on its own. A stray `jj new` (or `jj squash`, or a `git commit` in
this colocated repo) moves `@-` and empties that delta, so `ccjj audit` reported
"every changed path is claimed" at the exact moment the work was swept into an
unnamed commit. Drift from the recorded base is what makes that visible; `ccjj
commit` re-baselines every session afterwards so its own commit does not read as
someone else's.

When drift is detected, `audit` also **names the operation to undo**. Nothing
records who moved `@-`, so it replays the operation log asking "was `@-` still
the recorded base here?" — the newest operation that says yes is the last good
state, and the one immediately after it is the culprit:

```
session 6272e5cc started from 6e5d2c80, but @- has moved.
  6e5d2c80 was moved by operation 825b704ec100 (commit aff3f739…).
  Undo with:  jj op restore b5a8cf6c3dc3
```

The restore target is the **last good** operation, not the culprit — restoring
*to* the culprit would leave the stray commit in place. It rewinds the whole
repo, so anything else that happened since goes too; the message says so. Bounded
to 40 operations because each step is a `jj` process, though the stray commit is
almost always recent enough to resolve in two or three.

## State

```
$XDG_STATE_HOME/cc-jj-journal/<repo-root-with-slashes-as-underscores>/
    <session_id>/<nanos>-<pid>.json      live records
    <session_id>/<nanos>-<pid>.win       Bash windows (offers, never claims)
    <session_id>/.last                   rolling snapshot id for the next window
    <session_id>/.owner                  owning claude pid + start time
    <session_id>/.base                   the @- this session started from
    archive/<YYYY-MM-DD>/<session_id>/   retired
```

`ccjj prune` retires journals whose owning process is gone and which are older
than `--stale-days` (2), and deletes archived days older than `--days` (14). A
recent orphan is left alone — the session may have just crashed and its work is
still committable. `ccjj disown <sid>` retires one by hand.

The repo key matches `fish/functions/ai_jj_commit.fish:52` byte for byte, so both
tools show the same repo names in the state directory. Journals are **moved** to
`archive/` rather than renamed in place, so "scan every claim" sweeps cannot
re-count them. `ccjj prune` drops archived days older than 14 and is called
automatically, at most once a day, after a successful commit.

## Files

| Path | Role |
|---|---|
| `lib/python/ccjj.py` | everything |
| `bin/ccjj` | shell entry point |
| `bin/commit-mine` | shim for `ccjj commit` |
| `bin/ccjj-bash-window` | `PostToolUse(Bash)` shell pre-gate |
| `rcs/claude-settings.json` | hook registration (**never** edit `~/.claude/settings.json` — same inode, and `ensure-rcs.sh` blocks it) |
| `tests/lib/python/test_ccjj.py` | regression suite, one test per defect above |
