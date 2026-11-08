# Review of commit 9884e077 (ccjj fixes)

Reviewed on 2026-11-08 at the committed tree. All experiments ran in throwaway jj
repos with `CC_JJ_JOURNAL` isolated. They drove the real `record-edit` and
`bash-window` hooks. `old` is the parent's `ccjj.py`. `new` is the committed one.

## Verdict

The patch does what the report's sections say. I found no path that loses work or
commits another session's work.

`keep_unreplayed` adds one serious regression and one moderate regression. Both come
from restoring `.owner` and `.last` after a commit. A one-line change fixes both.
`--also` has a smaller regression through directory symlinks.

| # | Severity | Finding |
|---|---|---|
| 1 | HIGH | Restored `.last` makes the next `commit-mine` stop with a false exit 5 |
| 2 | MEDIUM | Restored `.owner` keeps a resumed session "ended" across commits |
| 3 | MEDIUM-LOW | `--also` through an in-repo directory symlink reports success and commits nothing |

`cmds test lib/python/test_ccjj.py` passes (117 ccjj tests) with all three defects
present.

---

## Finding 1: HIGH. Restored `.last` creates a window over work already committed

**Where:** `lib/python/ccjj.py:1952` and `:1960` (`keep_unreplayed`). The effect appears
at `:648` (the window is no longer skipped) and `:1267-1271` (the `loose` check).

**Cause.** `.last` holds the `@` id from the session's previous Bash call. The patch
copies it back after a commit. `commit-mine` is itself a Bash call, so its PostToolUse
hook fires next and records a window from that old id to the new `@`. The window spans
every Edit made since the previous Bash call. Those Edits are already in `@-`, but the
tree diff still lists them. The `loose` check does not compare with `@-`.

Before the patch the directory was gone, so this hook call only set a baseline.

**Scenario** (checkout with Bash windows on and contended, as `~/dotfiles` is):

1. Run any Bash call. Then Edit `a.txt`.
2. Run `commit-mine -m first`. It exits 0. The hook records a window that covers `a.txt`.
3. Edit `b.txt`. Run `commit-mine -m second`.

**Evidence** (reproduced, same steps on both versions):

```
old  commit-mine #2  rc=0  committed and verified 1 path(s): b.txt
new  commit-mine #2  rc=5  1 path(s) changed inside your Bash windows are not claimed,
                           and would NOT be committed: a.txt
```

`a.txt` was already committed. The message is false.

**When it fires.** It needs an Edit after the session's last hooked Bash call, then
`commit-mine`. `ai_jj_commit` matches, because `--diff` and the commit run inside one
Bash call. A session that runs `ccjj audit` first, as `/cc:commit` says to, moves `.last`
past the Edit and avoids it (reproduced: both commits exit 0).

**Why the real commit did not show it.** The daily prune retired the restored directory
in the same run (see Question 5). A second commit today does not get that.

**Other effects.**

- The false window is a stake for peers until the session's next commit. Reproduced: S2's
  `--also a.txt` exits 1 with `a.txt (S1 (live))` after S1 had committed that path.
- The exit-5 message offers `--no-claim`. That flag also drops real Bash work on other
  paths. `ccjj claim a.txt` is the harmless exit, and it worked in the repro.

**Fix.** Restore only the records. Change `:1952` to `keep = []`, or remove the `keep`
code. `.last` then behaves as before the patch: the next Bash call sets a baseline.
I ran this variant. The repro passes and all 117 tests pass.

**Add a test.** Window on, hook, Edit, `commit-mine`, hook, Edit, `commit-mine`. Assert
exit 0 on the second commit. No test covers `.last` here (see Question 2).

---

## Finding 2: MEDIUM. Restored `.owner` keeps a stale owner after a resume

**Where:** `lib/python/ccjj.py:1952`, with `stamp_owner` at `:330`, which never overwrites.

The missing `.owner` rewrite after a resume is already known. This finding is different:
the patch removed the one thing that repaired it. Before the patch a commit removed the
directory, so the next hook stamped the new process. Now the dead owner is copied back.

**Scenario.** A session crashes and is resumed. It commits with `commit-mine`, then keeps
editing. A peer asks `should-scope`.

**Evidence** (reproduced, prune already stamped for today):

```
old  .owner after next edit: <live pid>       should-scope as peer  rc=0  S1
new  .owner after next edit: <dead pid>       should-scope as peer  rc=1
```

With rc 1 the peer's `ai_jj_commit` takes the whole-copy route. That commits the resumed
session's unfinished edit under the peer's message, then `retire-all` archives its journal.

**Fix.** Same as Finding 1. An absent `.owner` counts as alive (`owner_alive`), so nothing
needs it restored, and the next hook stamps the correct process. Verified: the repro gives
the live pid and rc 0.

---

## Finding 3: MEDIUM-LOW. `--also` through a directory symlink commits nothing

**Where:** `lib/python/ccjj.py:1175`.

`rel_literal` keeps symlinks in every component, but only the last one should stay
unresolved. For `ln/f.txt`, where `ln` links to `real`, `lexists` passes and the fileset
matches nothing. `tests/roleplay` is a tracked link of this shape.

**Evidence** (reproduced):

```
old  --also ln/f.txt, with another path   rc=0  took ... wholesale: real/f.txt   committed
new  --also ln/f.txt, with another path   rc=0  took ... wholesale: ln/f.txt     NOT committed
new  --also ln/f.txt, only path           rc=2  "nothing of yours differed from @-"
```

The first `new` line is a false success. A following note does list `real/f.txt` as
unclaimed. The peer-stake check also looks at the wrong path in this case.

**Fix.** Resolve the parent and keep the leaf:

```python
also = [rel_literal(os.path.join(
            os.path.realpath(os.path.dirname(os.path.join(caller_cwd, p))),
            os.path.basename(p))) for p in args.also]
```

Verified: both repros now commit `real/f.txt`, and `test_also_names_a_symlink_not_its_target`
still passes. `claim` uses `rel_literal` too, but that was already so before this commit.

---

## Question 2: are the tests real?

**Payload shape is real.** The fields that `_hook_edit` and `_hook_write` send match
`toolUseResult` in the 40 newest transcripts (101 Edit, 26 Write). `replaceAll` was a
bool in all 101. `structuredPatch` is fake, but the hook only tests that it is truthy.

**Each new test and each changed test failed under at least one targeted mutation.** I ran
24 single-line mutations. 16 were killed. The 8 below survived the whole file (117 pass):

| Mutation that survives | What is unpinned |
|---|---|
| `.owner`/`.last` not restored | All of Findings 1 and 2. Nothing tests this code. |
| Write `content` taken from `tool_input` | Only `old`/`new` are pinned in the applied-strings test |
| `replace_all` taken from `tool_input` | Same |
| Peer exemption removed from `check_new_files_against_disk` | Would refuse a new file a peer also edited |
| Claim stake check on `path` only, not `src`/`tgt` | The rename half of the moved check |
| `refresh_bases` skips a session with no `.base` | The `""` case |
| `load_records(jdir)` instead of the `loaded` list | Needs a race between two adjacent calls. Not worth a test. |
| "Bash windows" hint removed | Message text only |

The report said every new test fails against its defect. That is true. It does not show
that every line of each fix is pinned.

## Question 3: commit contents

The commit holds exactly the 5 paths. `bin/shadow-*` and `rcs/claude-settings.json` are
not in it. The committed patch applied to the parent gives files byte-identical to the
committed `ccjj.py` and `test_ccjj.py`. Live `~/.claude/CLAUDE.md` matches the committed
`rcs/claude-user-claude.md`.

One small item: `.cc/ccjj-review-2026-11-07.md:15-24` and `:589` cite scratchpad files.
The `repro/` directory is already gone.

## Question 4: the new CLAUDE.md section

It does not contradict the rest of `rcs/claude-user-claude.md`. Two gaps remain:

- `~/dotfiles/CLAUDE.md:295-298` lists only `pending-updates-*` and `PLAN-*` as `.cc/`
  contents. Reports, reviews, patches and scripts are now normal there. Add them.
- The rule is global, and `!.cc` in `git/gitignore_global` makes `.cc/` trackable in every
  repo. It has no privacy caveat. `~/dotfiles` is public per its own CLAUDE.md, and the
  committed review's section 6 quotes the user's words from private transcripts. In a
  `~/projects/work/` repo a whole-copy commit would take these files too. Add one line:
  no private material in `.cc/` in a public or shared repo.

Confirm that section 6 is acceptable before the next push.

## Question 5: "retired orphaned journal" for six sessions

**The retirements were safe.** `retire` only moves a journal to `archive/<date>/`, kept 14
days. It does not touch the working copy. Today's six:

| Session | Records | Windows | Note |
|---|---|---|---|
| 1b8444b7 (ran the commit) | 0 | 0 | only `.base`, `.last`, `.owner` |
| 7f739092, 8622373a, 8c21bd7f | 0 | 0 | empty, owners dead |
| 4a0e7080 | 8 | 11 | owner dead, last activity Nov 5 18:00 MST |
| c69fa0f5 | 7 | 9 | owner dead, last activity Nov 5 13:03 MST |

The 5 real records of 1b8444b7 went to the archive under its plain name as `committed`.
The orphaned entry held nothing. A dead session's claims never suppressed audit warnings,
so retiring the last two changes no report about uncommitted work.

**The patch changed this for the committing session only.** Before it, the directory did
not exist after a commit. Now `keep_unreplayed` recreates it with no records, so
`journal_age_hours` is infinite. With a dead owner the prune in the same run retires it
and prints "owner gone" about the session that is running. Reproduced: `old` prints
nothing, `new` prints that line. The fix for Finding 1 removes it. The other five would
have been retired by the old code too.

**The remaining risk is old, and it affects attribution, not content.** A session resumed
after its records passed 48 hours is swept before its next edit. Reproduced on both
versions: its `commit-mine` then says "nothing recorded" (rc 2). The files stay on disk,
and the records can be moved back from `archive/`. Recent records are never swept,
because a fresh record makes the journal young.

The sweep also repaired the stale owner by accident. The journal for 1b8444b7 now shows
owner 3411, the live process, because the directory had to be recreated. This will not
happen on later commits (Finding 2).

## Checked with no defect found

- A two-session flow on one shared file: with `--no-claim`, each commit took only its own
  hunk, and both landed. Without `--no-claim`, both versions stop with exit 5 on the
  shared file. That is the claim cycle in report section 2.15.
- `applied()`: `old`/`new` from `tool_response` is no worse than `tool_input`. In 129 recent
  journal Edit records every `old` occurs in `original`.
- `drop_vanished`, `check_new_files_against_disk`, `refresh_bases(old_base=)`, the moved
  `claim` stake check, and the mid-commit Edit path.

One accepted cost is confirmed as common. In the two-session flow, a Bash-made file is
inside the peer's next window, so both `claim` and `--also` refuse it and only `--force`
works. The old `--also` let it through.
