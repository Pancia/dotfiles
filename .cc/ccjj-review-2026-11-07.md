# ccjj / commit-mine review — 2026-11-07

Scope: `lib/python/ccjj.py` (2136 lines), `bin/ccjj`, `bin/commit-mine`,
`bin/ccjj-bash-window`, `tests/lib/python/test_ccjj.py`, `docs/cc-jj-sessions.md`,
`fish/functions/ai_jj_commit.fish`, `ai/commands/commit.md`, the two `.cc/` notes,
the live journal under `~/.local/state/cc-jj-journal/_Users_anthony_dotfiles/`,
and past transcripts.

Nothing tracked in `~/dotfiles` was edited. All reproductions ran in throwaway jj
repos under the scratchpad with `CC_JJ_JOURNAL` isolated, and they drove the real
hooks with payloads shaped like Claude Code's. The one command run against the real
repo was a read-only `ccjj audit`, which takes a jj snapshot the way every hook
already does.

The patch landed in commit `37fb347f`, and the patch file was then removed. It
covered `lib/python/ccjj.py` and `tests/lib/python/test_ccjj.py`. The repro scripts were in a scratchpad that a reboot
erased.

---

## 1. Current state

**Tests: everything passes.** The ccjj file has 106 tests (97 `def test_`, some
parametrized), and all 106 pass on the current code. The full suite gave
`PASSED — 9 components, 1743 passed`.

> Tooling trap: the brief's command, `cmds test tests/lib/python/test_ccjj.py`, does
> **not** run one file. `run_tests.py` checks `TESTS_DIR / arg`, so the
> `tests/`-prefixed path matches nothing and falls through to "pass through to
> run_all as pytest args". The result is all 9 components, with `test_ccjj.py` added
> to each, so the file runs 9 times in ~15 min. The correct spelling is
> `cmds test lib/python/test_ccjj.py`.

**What works, and was checked by reading code and running repros:** the main replay
path (anchored replace, `replace_all` count check, merge3 for Write, bytes end to end,
already-applied detection), the shared lock plus flock, the parent pin and re-check,
the post-commit byte check plus rollback, the empty-commit refusal, merge-working-copy
refusal, inode-based path containment, `forget` (landed in `f3b3153b`), the nudge,
and Bash-window recording, narrowing and claim.

**Plan status** (`.cc/PLAN-ccjj-journal-fixes.md`, 2026-08-15). Only one of its six
steps has landed:

| Plan step | Status in code |
|---|---|
| `peers_with_a_stake()` shared by `--also` and `claim` | **not done**. `ccjj.py:1098-1109` is still records-only and live-only. In the patch. |
| `ccjj forget` | **done** (`ccjj.py:1877`) |
| Bug 1 `applied()` (record `tool_response` strings) | **not done**. `ccjj.py:512-515` still reads `tool_input`. In the patch. |
| Bug 3 existence filter before `build()` | **not done**. `build()` still never looks at the disk. In the patch. |
| Byte-verify `--also`; superseding `claim` | **not done**. Sketched in §2.14 and §2.15, not in the patch. |
| Test work (hook-shaped records, run the advertised `claim`) | **not done**. The patch adds 11 hook-shaped tests. The CRLF test and the never-run `claim` remain as they were. |

The plan's line numbers are now about 100 lines stale.

**Live journal (real repo, read-only).**
- `.jj/ccjj-contended` was written **Jul 31** and never cleared (see §2.11).
- `ccjj audit` reports 9 sessions with a drifted base. It also reports 7 sessions as
  "ended, never committed" with claimed paths. That is false for at least one of
  them: the only path `82d3436a` claims, `bin/claude-statusline`, was committed at
  21:12 MST by a plain `jj commit`, not by `commit-mine` (see §2.9).
- `99143d8d`, which the brief thought might be live, is not: its owner pid 68919
  (started Nov 5) is gone.
- `8c21bd7f` is live and has no records.

---

## 2. Defects and unfinished work (most severe first)

Each item below was reproduced, unless it says otherwise. "rc" is the exit code.

### 2.1 HIGH — `should-scope` sends a session with no records down the whole-copy path while a peer is live

**Evidence.** `cmd_should_scope`, `ccjj.py:1820-1823`, exits 1 unless *this* session
has a `.json`. `r_scope.py` sets up a live peer B with an uncommitted Edit. Session A
has only Bash work, and session C has no journal at all:

```
should-scope as A (bash-only, live peer B) -> rc=1
should-scope as C (no journal at all, live peer B) -> rc=1
```

On rc 1:
- `ai_jj_commit.fish:47-51` falls through to `jj describe` and `jj commit` of the
  **entire working copy**, which takes B's unfinished edit under A's message. It then
  runs `ccjj retire-all` (`:338`), which archives B's journal. B's next
  `commit-mine` says "nothing recorded", and B's work now sits in A's commit with no
  signal.
- `/cc:commit` (`ai/commands/commit.md:88`) says the same thing: "If `ccjj
  should-scope` exits non-zero (the usual case — you are the only session here),
  ignore all of the above". That premise is false here.

This is the exact failure the tool exists to prevent. The likeliest trigger is
common: an agent that worked only through Bash, or a fresh session asked to "commit
stuff". The behaviour is **pinned by a test**,
`test_should_scope_declines_with_no_records_of_my_own` (`test_ccjj.py:994`).

**Fix (in patch).** Drop the own-records gate, so the routing question becomes only
"is anyone else live here". A session with nothing recorded then gets
`commit-mine`'s rc 2 "nothing recorded". When the session has windows, that message
now also points at `ccjj audit` / `ccjj claim`. The pinned test is inverted. Pair
this with §2.10 so that `ai_jj_commit` passes the rc 2 through instead of
misreporting it.

### 2.1b HIGH — after `/clear` or auto-compaction, a session's own earlier edits belong to a "live peer"

Auto-compaction and `/clear` start a new session id in the **same** `claude`
process. This is documented in `~/dotfiles/CLAUDE.md` (ccs section) and in the
`session_is_live` docstring. The journal is keyed by session id, so the
pre-compaction journal becomes a separate session. Its owner is the same live pid,
and its records are under 12 h old, so it counts as a **live peer** of its own
successor.

`r_compact.py` sets up journals PRE and POST with the same `.owner` and nobody else
present:

```
should-scope as POST (alone, but compacted once) -> rc=0   "PRE"
commit as POST -> rc=0   "committed and verified 1 path(s): g.txt"
    f.txt in @-: 'f\n'                                  # the pre-compaction edit: left behind
audit as POST  -> rc=0   "session PRE (live) claims 1 path(s) / nothing unclaimed"
commit --also f.txt as POST -> rc=1  "a live session is working on them"
```

So a lone long-running session gets a **silent partial commit** after every
compaction. The result reports "verified", and audit says all-clear for up to 12 h.
In that window it is also told by the nudge that "another Claude session" is
working, which is itself. The transcript review found a related report for
`--resume` (cfcf43b2, 10-02: the resumed session gets a new id and no longer owns
its earlier edits). I did not re-verify that one.

**Fix (sketch, not in patch).** `$CLAUDE_PID` is set in the agent's own Bash
environment (checked: `CLAUDE_PID=2978` here), so `commit-mine` can identify its
process. Treat journals whose `.owner` equals `"$CLAUDE_PID\t$(ps lstart)"` as
**self**:

```python
def same_process_sids(me):
    pid = os.environ.get("CLAUDE_PID", "")
    own = "%s\t%s" % (pid, ps_lstart(pid)) if pid else None
    base = os.path.join(journal_root(), repo_key(ROOT))
    out = []
    for s in (os.listdir(base) if own and os.path.isdir(base) else []):
        if s in ("archive", me):
            continue
        try:
            if open(os.path.join(base, s, ".owner")).read().strip() == own:
                out.append(s)
        except OSError:
            pass
    return out
```

Then:
- `other_live_sessions()` excludes these journals, which fixes should-scope and the
  nudge.
- `cmd_commit` loads their records too, merged by filename. Filenames are
  `t_ns-pid`, so sorting keeps the order.
- The commit retires those journals with its own, and prints one line naming them.

For `--resume`, where the process differs, add `ccjj adopt <sid>`. It would move an
**ended** session's records into this one after printing them. With the §2.2 fix,
`--also` of an ended session's path needs `--force`, so the resume case needs a
named route.

### 2.2 HIGH — `--also` peer-stake check is weaker than `claim`'s, and `claim` routes deletes past its own check

The `.cc/ccjj-also-leak-verdict.md` findings are **re-confirmed on the current code**
(`r_also.py`):

```
claim peer.txt -n (A)                       -> rc=1  "also claimed by session(s) B (live)"
commit --also peer.txt (A)                  -> rc=0  peer.txt in @-: 'peer SECRET-B unfinished\n'
commit --also peer.txt (A), B ended         -> rc=0  peer.txt in @-: 'peer SECRET-B unfinished\n'
claim peer.txt (A) [A deleted it via Bash]  -> rc=1  "commit it with: commit-mine ... --also peer.txt"
commit --also peer.txt (A)                  -> rc=0  peer.txt in @- files: False
```

The check at `ccjj.py:1098-1109` looks only at `other_live_sessions` × `claims_of`,
which means records only and live peers only. The `claim` check at `:1452-1470` looks
at all peers, and at records **or** windows. `claim`'s removed/renamed redirect
(`:1399-1410`) runs **before** its peer check, so following the tool's own printed
advice commits, or deletes, a peer's work at rc 0. The doc table in
`docs/cc-jj-sessions.md:137` says this was already fixed (see §3).

**Fix (in patch).** One `peers_with_a_stake(path, me, cov)` returns
`{sid: live|ended}` from records or windows of every other session. Both `--also` and
`claim` use it. `claim` runs it before the delete/rename redirects, covering `src`
and `tgt` too.

Accepted cost: an ended peer whose window spanned *your* change now also blocks
`--also`. That is the same false positive `claim` already has, and `--force` after
reading the diff is the way out.

### 2.3 HIGH — the journal resurrects deleted files (plan bug 3), including silently at rc 0

`r_bug3.py`, current code:

| Case | Result |
|---|---|
| Edit, then `rm` (path in `@-`) | **rc 0, "committed and verified"**; `gone.txt` in `@-` is `'LINE1\nline2\n'`, but it is gone on disk |
| Write v1, `rm`, re-create v2 via Bash | **rc 0**; `@-` holds `'SECRET v1\n'`, disk holds `'v2 via bash\n'` |
| Write, then `rm` (new path) | rc 1, "the commit did not take", which recommends `disown`. The whole session is wedged. |
| Empty Write, then `rm` | **rc 0**, "committed and verified 2 path(s): empty.txt, …", but `empty.txt` is not in `@-` |

Cause: `build()` (`ccjj.py:940-1018`) seeds only from `@-`, and nothing subtracts a
record. The byte check cannot tell absent from empty: `jj file show` returns `b""`
for both.

**Fix (in patch).** Two checks:
- `drop_vanished()` runs before `build()` and after `--also` has removed its paths.
  - For a new path that is gone from disk, its records are skipped with a note.
  - For a path in `@-` that is gone from disk, the commit refuses and names both
    exits: `--also <p>` commits the deletion, `ccjj forget <p>` leaves it.
- `check_new_files_against_disk()` runs after `build()`. It covers a path absent from
  `@-` whose reconstruction differs from the disk while no peer has a stake. It
  refuses and names `--also` / `forget`.

The check is restricted to new paths on purpose. For existing paths, a difference
from the disk is normal (peers, Bash) and stays the Bash-window check's job.

### 2.4 MEDIUM-HIGH — poisoned records: `record-edit` stores the *requested* strings, not the *applied* ones (plan bug 1)

`cmd_record_edit` (`ccjj.py:512-515`) takes `old`/`new` from `tool_input` and
`original` from `tool_response.originalFile`. The Edit tool normalizes the request
before applying it.

**Measured** with `scan_edits.py` over every transcript on disk: 657 Edit results
carry `originalFile`.
- `tool_input.old_string` was **not** a substring of `originalFile` in 1 of them.
  That one is in `1bc0322e`, the session that hit this bug.
- `tool_response.oldString` was a substring in **657/657**.
- 0 of the 657 `originalFile`s contain CRLF, so the CRLF variant can be neither
  confirmed nor refuted from data.

Repro (`r_misc.py`, curly-quote request against a straight-quote file):

```
ccjj: journal record for q.txt is inconsistent: its recorded pre-edit
  content does not contain b'say \xe2\x80\x9chi\xe2\x80\x9d'.
```

One such record refuses the **whole** commit.

**Fix (in patch).** `applied("oldString", "old_string")` and the same for `newString`,
`content` and `replaceAll`. Each prefers `tool_response` and falls back to
`tool_input`.

### 2.5 MEDIUM — Bash-created then Edited file: whole commit refused, the message misdiagnoses it, and `claim` refuses too

This is a common agent pattern: `cat > new.sh <<EOF`, then an Edit. `r_bashcreate.py`:

```
commit             -> rc=1  "new.sh is not in @- at all ... larger than snapshot.max-new-file-size (1MiB)"
claim new.sh -n    -> rc=1  "already has 1 recorded Edit/Write record(s) ... Commit them first"
commit --no-claim  -> rc=1  (same 1MiB message)
```

The same happens without Bash windows. Nothing says `--also new.sh` works, and it
does work, because `--also` excludes the path's records. The 1MiB explanation is the
rare case. The same message also appears when a *peer's* Write created the file.

**Fix (in patch, message only).** `anchored_replace`'s empty-target branch now names
the usual cause (heredoc, `cp`, generator, or a peer's Write) and the `--also`
route, and keeps 1MiB as the rare case. The structural fix is §2.15, the superseding
claim.

### 2.6 MEDIUM — `--also` on a symlink commits the target instead of the link

`cmd_commit` resolves `--also` with `rel()`, which realpaths (`ccjj.py:1062`). `r_misc.py`:

```
commit --also link (in-repo target)  -> rc=0  "took 1 path(s) wholesale, unverified: target.txt"
                                              link in @- files: False
commit --also ext-link (target outside repo) -> rc=1 "... is outside the repo.
                                              It cannot be committed here; remove its journal record"
```

The second message is wrong twice: no record exists, and the link *is* inside the
repo. If the target carries a peer's edit, that edit is the thing that gets taken.
`bin/hermes-native`, a real link out of the repo, is exactly this shape.

This has already happened. The transcript review found that in `ebd7b233`
(2026-08-07) it dropped three symlinks from a commit with no warning. `claim`
refuses symlinks and points at `--also`, so neither route worked. Neither the plan
nor the docs record it.

**Fix (in patch).** Use `rel_literal()`, which the code already has for exactly this
reason.

### 2.7 MEDIUM — `refresh_bases` erases another session's drift evidence

`refresh_bases` (`ccjj.py:381-398`) rewrites **every** session's `.base`, live or
ended, after each `commit-mine`. `r_misc.py`:

```
audit before A commits: drift reported: True
commit (A) -> rc=0
audit after A commits: drift reported: False   "session B (live) claims 1 path(s) | nothing unclaimed"
```

B's work had been swept into a stray `jj commit`. The drift report exists to say so,
and A's ordinary commit silenced it.

**Fix (in patch).** Re-baseline only sessions whose `.base` was the pre-commit `@-`
(`pinned`), or that have no `.base`. `retire-all` still refreshes all of them.

Trade-off: drift now persists until the drifted session commits, or is
pruned or disowned. There is no "acknowledge drift" command. See §2.12 for why drift
is already noisy.

### 2.8 MEDIUM — an Edit recorded during a commit is archived without being committed

`cmd_commit` loads records at the start and `retire()` moves the **whole directory**
at the end. `record-edit` takes no lock. `r_race.py` uses a jj shim that sleeps 2 s
inside `jj commit`, and fires a same-session Edit (a subagent) in that window:

```
commit rc=0: committed and verified 1 path(s): a.txt
live records for A: 0 | archived records: 2
b.txt in @-: 'b\n' | on disk: 'B-mid-commit\n'
commit again (A) -> rc=2  "nothing recorded for session A"
```

The edit stays on disk, but it can no longer be attributed. Triggers are subagents,
which share the session id, or `commit-mine` run in the background.

**Fix (in patch).** `record_names()` snapshots exactly what is replayed, and
`retire()` returns the archive path. `keep_unreplayed()` then moves any record that
was not replayed back to a fresh live directory, with `.owner` and `.last`. Keeping
`.last` also stops the next Bash call being spent on a new baseline.

### 2.9 MEDIUM — `/cc:commit`'s unscoped route never retires journals

`ai_jj_commit` runs `ccjj retire-all` after a whole-copy commit (`:338`). The
`/cc:commit` procedure (`commit.md:168-240`: `jj commit -m`, `jj commit <paths> -m`)
never does.

Live evidence: three plain `commit` operations ran at 21:12 MST (op log
`c80da5c8`, `f303138c`, `eb81c9a2`). The first of them committed
`bin/claude-statusline`, the only path session `82d3436a` claims. Audit still lists
`82d3436a` as "ended, never committed", and it is one of the 9 drifted sessions.

While such a session is live, its committed paths still count as claimed, so a later
Bash change to them by anyone is **not** reported. After the session ends, those
records generate permanent false "never committed" and drift noise until `prune`.

**Fix (not in patch; it is `commit.md`).**
- After a whole-working-copy commit, run `ccjj retire-all -q`, the same as
  `ai_jj_commit`.
- After a path-scoped `jj commit <paths>`, retire this session's records for exactly
  those paths. Today that would be `ccjj forget <paths>`, but semantically it wants
  its own verb or a `forget --committed` that archives instead of parking in
  `forgotten/`.

### 2.10 LOW-MEDIUM — `ai_jj_commit` turns every non-5 `ccjj` exit into "jj diff failed… stale or busy", rc 1

`ai_jj_commit.fish:230-233`. `ccjj commit --diff` exiting 1 (a refusal, with ccjj's
own reason already on stderr), 2 (nothing recorded) or 4 (locked, retry) is all
reported as a stale working copy and returned as **1**. That loses the retry contract
for 4 and the "nothing to do" contract for 2. This becomes common after §2.1's fix.

**Sketch (fish, not applied; needs `/fish` first):**

```fish
    if test $session -eq 1; and contains -- $jj_status 1 2 4
        # ccjj already explained itself on stderr; keep its exit contract.
        test $jj_status -eq 2; and echo "ai_jj_commit: this session recorded no committable changes" >&2
        return $jj_status
    end
```

### 2.11 LOW — `.jj/ccjj-contended` is never cleared

The nudge only sets it. Its comment (`ccjj.py:756-762`) says clearing "belongs where
the whole picture is known (prune / retire-all)", but `cmd_prune` never clears it.
Only `retire-all` and `bash-windows off` do. In `~/dotfiles` it has been set since
Jul 31, so the gate's "~78% of minutes uncontended" saving has not existed for three
months, and every Bash call pays the snapshot.

**Fix.** At the end of `cmd_prune`, clear the marker when `other_live_sessions("")`
is empty. That is safe, because the nudge re-sets it on the next prompt that sees a
peer.

### 2.12 LOW — `DRIFT_LIMIT = 40` operations is swamped by snapshot operations

Every hook snapshot is an op, so 40 ops is minutes of activity. Live audit prints
"Could not find where 51acde213ce4 was still current within the last 40 operations"
for 6 sessions. It also costs up to 40 jj processes on every `audit`.

**Fix.** Walk only non-snapshot operations, by filtering the op-log description on
`snapshot working copy` before probing, and raise the bound. Also skip drift
reporting for ended sessions whose base is older than the prune horizon.

### 2.13 LOW — refusal messages that name the wrong way out

- "the commit did not take" (`ccjj.py:1282-1290`) recommends `ccjj disown`, which
  drops **all** of the session's records. `ccjj forget <paths>` is the scalpel.
  Fixed in the patch.
- `rel()` says "remove its journal record and re-run" (`:193`). It also fires for
  `--also`, where there is no record, and names no command. §2.6 removes the
  `--also` case.

### 2.14 UNFINISHED — byte-verify `--also` (plan bug 2, step 2)

`--also` paths are reported "unverified" and are never checked. Sketch:
- Before `jj commit`, capture `working_copy_bytes(p)` for each `--also` path, with
  `None` when it is absent.
- After the commit, require that `@-` matches: `file_type_at("@-", p) == ""` for
  `None`, otherwise `file_bytes("@-", p) == want`, comparing symlinks by target.
- Roll back on a mismatch, the same as the `mine` check.

This is purely additive.

### 2.15 UNFINISHED — superseding `claim` (plan bug 2, step 3): the claim/commit cycle

A path with both records and a Bash change hits a cycle:
- `commit` exits 5 ("claim it"), because `mine[p] != disk` (`:1150-1151`).
- `claim` exits 1 ("commit them first", `:1420-1426`).
- The only ways out are `--no-claim`, which drops the Bash half, and `--also`, which
  is wholesale.

`test_stop_fires_when_a_journaled_path_also_changed_via_bash` (`test_ccjj.py:1799`)
asserts the message names `ccjj claim doc.md` but never runs it. §2.5 is the
new-file instance of the same cycle.

**Sketch.** When `claim` finds records of this session for the path, after the peer
check passes:
- Set the base to the first record's `original` when that record predates the first
  window that changed the path. Otherwise use `blobs[lo]`.
- Set the content to the current working-copy bytes, so Edits after the last window
  are included.
- Show that diff, then move the path's records to `forgotten/`, which makes the step
  reversible.
- Write one base64 `Write` record (`claimed: true`, `superseded: [names]`).

The existing merge3 path then handles it. Then invert
`test_claim_refuses_when_the_session_also_edited_the_file` (`test_ccjj.py:1358`), and
make the stop test actually run `claim` and commit.

### 2.15b UNFINISHED — you cannot split your own work into several commits under contention

One goal is to commit all changes as several separate commits. `/cc:commit` disables "Split everything" when `should-scope` exits 0
(`commit.md:148`), and `commit-mine` has no path filter. The transcript review
found agents getting around this with path-scoped `jj commit` (10-27) and scripted
`jj split` (10-02). Both take peers' hunks in shared files, and neither retires the
journal (§2.9).

**Sketch.** Add `commit-mine -m msg -- <paths>`:
- Restrict `scoped` to records whose `rec_rel` is in the paths.
- Retire only the records that were replayed. The §2.8 `keep_unreplayed()` in the
  patch already does this.

`/cc:commit` can then offer the split as N `commit-mine -- <group>` calls.

### 2.16 LOW — coverage gaps worth documenting

- `NotebookEdit` is not journaled. `record-edit` accepts only `Edit` and `Write`.
- The Bash gate keys on the payload's `cwd` only. A Bash command run from outside
  the repo that writes into it is never windowed.
- `cmds test tests/...` runs the whole suite, as noted in §1. That is a
  `run_tests.py` problem, not a ccjj one.
- `find_repo()` does not stop at a git worktree. Inside
  `.claude/worktrees/<name>/` of a jj repo it walks up to the parent's `.jj`. The
  worktree session then journals into the parent's journal and marks the parent
  contended. Source: the transcript review (cf3292a6, 08-01, a proposal nobody
  answered); I confirmed it from the code at `ccjj.py:143-153`. `cc-worktree`
  refuses `~/dotfiles`, so this affects other repos only. Fix: stop the walk and
  return None when a `.git` *file* is found before a `.jj`.

---

## 3. Docs and code disagree

1. `docs/cc-jj-sessions.md:137` says "`--also` validates the path and checks live
   sessions… in exactly the situation `claim` refuses by name". That implies parity.
   The code checks only live peers' records (§2.2).
2. `docs:217` ("What `claim` refuses") says "a path a **live** session claims". The
   code refuses ended peers too, and labels them "(ended)".
3. `ccjj.py:756-762` (nudge comment) says contention clearing belongs to "prune /
   retire-all". `cmd_prune` does not clear it. `docs:133` says `retire-all` only. The
   docs' "~78% of active minutes uncontended" cost argument has not held since
   Jul 31 (§2.11).
4. `docs:380-382` says "two `die()` messages instructed exactly that… Those messages
   now name the command". Only `anchored_replace`'s does. `load_records` says forget
   cannot help (true). "Did not take" names `disown`, and `rel()` names nothing
   (§2.13).
5. The `refresh_bases` docstring says "re-baseline every **live** session". The code
   rewrites every session directory (§2.7).
6. `ai/commands/commit.md:88` says "non-zero (the usual case — you are the only
   session here)". That is false when the session has no records of its own (§2.1).
7. The `~/dotfiles/CLAUDE.md` quick reference for `ccjj forget` points at
   `.cc/PLAN-ccjj-journal-fixes.md` "for the three bugs that motivated it". All three
   bugs are still open, and the plan's line numbers are stale.
8. `docs:266-268` lists three deliberate gaps in Bash windows. It omits that a
   window's coverage ends at each commit: `retire()` archives the windows, so Bash
   changes left with `--no-claim` can never be claimed later.

---

## 4. The patch

`ccjj-review-fixes.patch` (705 lines) covers §2.1–2.8 and the `disown` → `forget`
wording in §2.13. Verified two ways:

- **Patched tree:** 117/117 pass. That is 106 existing tests, 2 of them updated (the
  inverted should-scope test, and one message assertion), plus 11 new tests.
- **Original code with the new tests:** 13 fail. They are the 11 new tests plus the
  2 updated ones. So every new test fails against the defect it pins.

The new tests drive the **real** `record-edit` hook with Claude-Code-shaped payloads
(`_hook_edit` / `_hook_write`), not hand-built records. That answers the plan's
"test that cannot fail" concern for the new cases.

Not in the patch: §2.1b, §2.9 (commit.md), §2.10 (fish), §2.11, §2.12, §2.14, §2.15, §2.15b.

The patch was not run through a live two-session flow. Its peer check now calls
`window_coverage()` on every `--also`. That is one `jj diff` per session journal,
about 10 in the live state, so roughly 0.5 s.

---

## 5. Recommended order

1. **§2.1 should-scope**, together with **§2.10** (fish exit codes). This is the
   only defect reachable from the zero-effort path, "commit stuff", that commits a
   peer's work. The patch inverts one test. Then **§2.1b** (same-process journals
   count as self), which is the commonest silent partial commit for a lone
   long-running session.
2. **§2.2 shared stake check** and **§2.6 `rel_literal` for `--also`**. These close
   the remaining routes that commit a peer's work at rc 0. Land them before §2.15,
   whose safety argument depends on them.
3. **§2.3 existence filter** and **§2.4 applied strings**. These end silent
   resurrection and poisoned records.
4. **§2.8 keep unreplayed records** and **§2.7 drift preservation.**
5. **§2.5 message**, then **§2.15 superseding claim** (removes the cycle), then
   **§2.14 byte-verify `--also`.**
6. **§2.15b `commit-mine -- <paths>`**, which builds on §2.8, so that splitting
   is possible under contention.
7. Housekeeping: §2.9 (commit.md retire), §2.11 (clear contended in prune), §2.12
   (drift walk), and the doc fixes in §3. Then update or archive
   `.cc/PLAN-ccjj-journal-fixes.md` so it stops describing landed work as open.

---

## 6. From the transcripts

Mined by a sub-agent from cf3292a6, 6799690c, 826a454d, 1bc0322e, ebd7b233,
41f1a0d4, 8649a50c, cfcf43b2, d087f856 and 4a0e7080. Items it reported that I
reproduced or confirmed in code are folded in above (§2.1b, §2.6, §2.9, §2.12,
§2.16). What remains:

- **Resolved:** the partial commit reported as verified (07-31), fixed by the exit-5
  stop; and the path-case bug, fixed in `577cf71b` (08-07).
- **Adjacent, confirmed in code:** `bin/vcs-status-for-ai:50` walks the logical
  `$PWD`. From `~/.config/fish/functions`, a symlink into this checkout, it never
  finds `.jj`, so `/cc:commit` refuses there (cf3292a6, 08-01, a proposal nobody
  answered). Fix: start from `pwd -P`.
- **Own `chmod` is never committed** (documented limit). The transcripts count it
  as the commonest Bash-made repo change, 13 of about 30 (cf3292a6, 07-30).
  `parent_exec_bits()` forces `@-`'s mode on every path that exists there.
  `--also` is the only route, and it takes content wholesale. Suggested fix: let
  `claim` accept a mode-only window delta. It would record the new mode bit with
  no content, and `build()` would carry it into `modes`.
- **Resume rotates the session id** (cfcf43b2, 10-02). This is reported only; I did not verify it.
  If it is true, a resumed session is a different process, so §2.1b's
  same-process rule does not catch it. That is why §2.1b proposes `ccjj adopt`.
- `forget` was written on 08-15 but not committed until 10-02.
