# Automatic per-session worktree isolation — implementation plan

**Fourth draft. Third survived a critique that proved five blockers; those are
folded in below. The headline addition is slot-aware resume — without it,
isolation silently breaks `ccs`.**

`ccjj` handles `~/dotfiles`, which cannot be isolated (~46% of tracked files load
by absolute path). Every *other* repo can be, and there the right answer is the
ordinary one: **the wrapper creates a worktree and `cd`s in before launching
claude**, opt-in per checkout.

## Corrections to the second draft

| Was | Now |
|---|---|
| "git recovery is bad, cite the AKR merge-queue" | **Disproved.** Different files merge clean; same file, different lines merges clean; only same-line edits conflict, and `git merge --abort` recovers perfectly. Recovery is `git merge w-NN` from the repo root. **No merge queue. Both backends first-class.** The only friction is that the agent *inside* the worktree cannot run it (`fatal: 'master' is already checked out`) — so the wrapper does it at exit. |
| Reaper does `git branch -D` | **`-d`.** Verified: `-d` refuses an unmerged branch (rc 1) and leaves it as the recovery handle. `-D` would destroy the commits the reaper just went to the trouble of preserving. |
| Link list "linked or copied" | **Symlinked, always.** A symlink cannot be destroyed by removing the worktree — which retires draft-one's defect 1 for every listed path. `copy:` prefix for the rare path that must diverge. |
| — | **New hazard (jj only): jj auto-tracks.** A symlinked `node_modules` in a jj workspace gets snapshotted as a symlink pointing into the parent and committed. `cc-worktree on` must refuse in a jj repo until every link-list entry is ignored. |
| Slot released unconditionally at exit | **`.hold`.** A slot whose work is not safely in the repo is held and never reaped. Without it, a conflicted merge leaves the branch and then a later reaper trashes the worktree. |

Everything else from draft two stands, including the two defects that killed
draft one (ignored files destroyed by a "safe" remove; a fresh worktree having no
`.cc-config` / `.claude/` because `gitignore_global` line 2 is `.*`).

## Corrections to the third draft

| Was | Now |
|---|---|
| `ccs` re-keyed to the parent, resume assumed to work | **PROVEN broken.** `claude --resume` is scoped to the project directory (`~/.claude/projects/<mangled-cwd>`), so a session that ran in `w-01` cannot be resumed from the parent. Re-keying made it *worse*: pre-change `ccs list` inside `w-01` worked; post-change the entry surfaces at the parent and resume fails. **Fix: slot-aware resume** — see its own section. |
| `jj log -r 'w-NN@' -T empty == false` | **PROVEN never fires.** That emits `@  false` plus graph decoration. Needs `--no-graph`, **and** `jj -R <wt> st` first, because the parent only sees what the workspace last snapshotted. As written the jj exit path always released — uncommitted work straight to the trash. |
| `set -l target (cc-worktree create … 2>&1)` | **PROVEN broken.** `create` prints warnings on the success path (dirty parent, subdir fallback, submodules); `2>&1` folds them into the capture, fish says `Too many args for cd` and **`$status` is still 0**, so the wrapper runs un-isolated while the slot is claimed. Path on **stdout only**, every warning on **stderr**, no `2>&1`, and `cd $target[-1]`. |
| Dirty-at-exit ⇒ HOLD, treated as exceptional | It is the **normal** case (Ctrl-C mid-task, "commit later"). Ten uncommitted exits from one terminal exhaust `MAX_SLOTS`. Added **`cc-worktree land`**, and `release` now refuses without `--land` or `--discard`. |
| Reaper branches only on owner/dir/hold | It **trashes uncommitted work** while the exit path holds it — and SIGKILL / `Cmd+Q` / `tmux kill-session` all skip the exit path, so the crash case is exactly the one that loses work. Reaper now applies the **same dirty test** and writes `.hold "uncommitted (crashed)"`. |
| `_cc_worktree_key` defaults to `pwd -P` | Every `ccs` site it replaces uses **logical** `pwd`. `/tmp`→`/private/tmp` and `~/Cloud` (a ProtonDrive symlink) diverge, silently orphaning existing entries. Use `$PWD`. |
| Nesting refused in `on` | `create` never checked. In a linked worktree `--git-common-dir` finds the parent's marker, so `w-01/.claude/worktrees/w-02` is reachable — and the design *invites* it, because resolving a hold sends you into the worktree. `create` runs the same detector. |
| `.owner` written once, atomically, **and** records `branch` | Contradiction: the branch is not known until after the claim. Claim with `branch: null`, then `os.replace` the completed record — rename is atomic, so the no-empty-window property survives. |
| Reaper reads the branch at step 4 | Step 3 (`git worktree prune`) destroys its source, and the `missing .owner` row never had one. Capture `git worktree list --porcelain` **once at the top** and carry it through, or branches orphan and every later `create` takes the `w-NN-<stamp>` fallback forever. |
| Exit merge: conflict or "other err" | The likeliest failure is neither: with an uncommitted parent edit to a touched file, `git merge` fails `Your local changes would be overwritten` rc 1 on what was a **fast-forward**, and `git merge --abort` then exits **128** (`no merge to abort`). Detect it and print `git stash && git merge <branch> && git stash pop`. |
| Merge target implicit | It is whatever the parent has checked out **now**. Record the parent's branch in `.owner` at create; if it moved, HOLD and name both. |
| Reaper takes no lock | Two `cc` launches racing: one's `git worktree prune` can drop a registration the other's `git worktree add` is mid-creating (no expire grace — verified). Take the `flock` the way `ccjj` does. |
| Trash failure unspecified | `bin/trash` exits 1 on failure. Continuing past it to prune + `rm .owner` leaves a non-empty directory at the slot path, and `git worktree add` then hard-fails there **forever**. A nonzero trash **aborts the release** with `.owner` intact, and reports. Note also: `trash` moves to `~/.Trash`, so a repo on another volume makes release a full cross-device copy — on the critical path of every `cc`. |

## Facts this plan is built on

Verified; do not re-derive.

| Fact | Consequence |
|---|---|
| `git worktree remove` without `--force` returns 0 and **deletes ignored files** | trash, never delete |
| jj has no surfaced untracked concept | the "check for untracked" guard is unimplementable; trash is the answer for both |
| `gitignore_global:2` is `.*` → `.claude/`, `.cc-config`, `.envrc` absent from a fresh worktree | the link list is mandatory, not a nicety |
| `git rev-parse --git-dir` ≠ `--git-common-dir` in a linked worktree; equal in the parent | nesting detector (git) |
| `.jj/repo` is a **file** in a workspace, a **directory** in the parent | nesting detector (jj) |
| `.git` is a *file* in a linked worktree and in submodules | marker must use `--git-common-dir` |
| `git worktree prune` clears a registration whose directory is gone; the branch survives | trash-then-prune is safe |
| `git merge w-NN` from the parent root works with an unrelated dirty file | exit-path merge is ordinary |
| `jj workspace add` bases on `@-`, not the dirty working copy | warn when the parent is dirty |
| `jj workspace forget` leaves the directory on disk; exits 0 on an unknown name | idempotent reaping |
| After `forget`, the working-copy commit is **not in the default revset** | bookmark **before** forgetting |
| `w-NN@` resolves from the parent (`jj log -r 'w-NN@' -T empty`, `jj bookmark set -r 'w-NN@'`) | the reaper and exit path never enter the workspace |
| The parent sees only what that workspace **last snapshotted** | the bookmark recovers snapshotted work only; the trash covers the rest |
| `git worktree add` leaves submodules empty | `git submodule update --init --recursive` after add |
| `$fish_pid` is stable per terminal | pid-derived names collide on relaunch → stable slots |
| `~/.claude.json` has ~593 project entries | slot reuse bounds new entries at `MAX_SLOTS` per repo |
| jj bookmarks are repo-global | inside a workspace, `jj commit` + `jj bookmark set master -r @-` really advances master |

## Files

| Path | Responsibility |
|---|---|
| `lib/python/cc_worktree.py` | All logic: marker, link list, slot allocation, create, reap, release, merge, hold, status. |
| `bin/cc-worktree` | `exec python3 .../lib/python/cc_worktree.py "$@"` — same two-line shape as `bin/ccjj`. |
| `fish/functions/_cc_worktree_key.fish` | Pure-fish, no subprocess: map a worktree path to the parent repo path. Used by the wrapper and by `ccs`. |
| `fish/functions/my-claude-code-wrapper.fish` | Modified — see below. |
| `fish/functions/ccs.fish` | Re-keyed — see below. |
| `fish/functions/chpwd.fish` | One extra line: held/active slot count. |
| `docs/cc-worktree.md` | User doc, in the shape of `docs/cc-jj-sessions.md`. |
| `tests/lib/python/test_cc_worktree.py` | Logic tests. Component `lib/python` is already registered. |
| `tests/fish/test_cc_worktree_wrapper.py` | Wrapper + key tests, pytest driving `fish -c`. Component `fish` is already registered. |

Python, not fish, for the same reason `ccjj` is: the ordering rules are the hard
part and they need real tests. `bin/trash` is a fish shim callable from anywhere,
so trashing from Python is one `subprocess.run(["trash", path])`.

**REQUIRED: run the `/fish` skill before touching any `.fish` file in this plan.**
Four files here are fish. Repo rule, no exceptions.

## State

```
<repo>/<git-common-dir | .jj>/cc-worktree      opt-in marker AND link list (one file)
<repo>/.claude/worktrees/w-01/                 the isolated working copy
<repo>/.claude/worktrees/w-01.owner            JSON identity — see below
<repo>/.claude/worktrees/w-01.hold             present ⇒ never reap; body says why
$XDG_STATE_HOME/cc-worktree/repos              opted-in repo roots, for `reap --all`
```

`.owner` — written once, atomically, as the claim itself:

```json
{"pid": 4711, "pid_lstart": "Wed Jul 30 22:31:07 2026", "slot": "w-01",
 "branch": "w-01", "backend": "git", "repo": "/Users/anthony/projects/x",
 "cwd": "/Users/anthony/projects/x/src", "created_at": 1753900000}
```

`pid` is `$fish_pid` (the wrapper's shell), matching `_ccs_open_register $fish_pid`.
Liveness is pid **+** `ps -o lstart=`, the same check as `ccs.fish:818` and
`ccjj`'s `.owner`. `branch` is recorded rather than derived because it is not
always `w-NN` (see allocation).

## Marker and link list

The marker file *is* the config. Empty ⇒ defaults. `#` comments ignored.

```
# <repo>/.git/cc-worktree
.cc-config
.claude/settings.json
.claude/settings.local.json
.envrc
node_modules
.venv
copy:.tool-versions
```

- Every entry is **symlinked** into the worktree, absolute, parent-pointing.
  Edits inside the worktree therefore land in the parent — which is what you want
  for `.env`, `.envrc`, `node_modules`, `.venv`, and for permission grants
  accruing to `settings.local.json`. It also means removing the worktree destroys
  none of them.
- `copy:` prefix copies instead, for the rare path that must diverge.
- Missing entries are skipped silently; that is the normal case.
- Parent directories are created (`.claude/` before `.claude/settings.json`).
- Defaults when the marker is empty: the first four lines above.

`cc-worktree on` validates the list and **refuses** rather than warns when:

| Condition | Why |
|---|---|
| repo root is `~/dotfiles` | cannot be isolated; that is what `ccjj` is for |
| already inside `*/.claude/worktrees/` or a linked worktree/workspace | no nesting |
| **jj**: any link-list entry is not ignored | jj auto-tracks. Verified procedure: create a probe workspace, link the list, `jj st`; refuse and name the paths unless it is empty. A tracked symlink into the parent gets committed. |

and **warns** when: git and an entry is not `git check-ignore -q` clean; the repo
has submodules (slow to populate, no jj equivalent); the working copy is dirty.

## Slot allocation

`MAX_SLOTS` = 10, overridable in the marker (`max-slots: N`).

```python
for n in range(1, MAX_SLOTS + 1):
    slot = f"w-{n:02d}"
    tmp  = wt / f".{slot}.owner.{os.getpid()}"
    tmp.write_text(json.dumps(record))          # fully formed BEFORE it is visible
    try:
        os.link(tmp, wt / f"{slot}.owner")      # atomic; EEXIST loses the race
    except FileExistsError:
        continue
    finally:
        tmp.unlink(missing_ok=True)
    return slot
raise NoFreeSlot(held=[...])                    # names every held slot + release cmd
```

Two shells racing cannot claim the same slot: `os.link` is atomic and fails
`EEXIST`. Writing the temp file first and hard-linking it in means there is **no
window where `.owner` exists but is empty** — a `create`-then-`write` claim has
one, and a reaper landing in it must either reap a live slot or invent an
age heuristic.

The reaper runs **before** allocation, so a stale `.owner` is already gone by the
time the loop starts. Slots are reused, which is what bounds `~/.claude.json`
growth and disk.

Branch naming: if branch `w-NN` already exists (left behind by a released-but-
unmerged slot), try `git branch -d w-NN`; if that refuses, use
`w-NN-<YYYYmmdd-HHMMSS>` and record it in `.owner`. `git worktree add -b w-NN`
hard-fails on an existing branch, so this is not optional.

**Known, accepted:** relaunching from a shell whose previous session crashed sees
the stale slot's owner as *alive* (same pid + lstart) and leaves it. That is the
conservative direction — the crashed session's work stays on disk — and it costs
one slot until the shell exits.

## Create

```
0. refuse if the repo root is itself a worktree/workspace -- the SAME detector
   `on` uses. `--git-common-dir` finds the parent's marker from inside a linked
   worktree, so without this `w-01/.claude/worktrees/w-02` is reachable, and
   resolving a hold sends you into the worktree in the first place.
1. reap                                          (under the shared flock)
2. claim slot                                    (.owner with branch:null, then
                                                  os.replace the completed record;
                                                  --slot/--reuse honours a
                                                  specific slot for resume)
3. git: git worktree add -b <branch> .claude/worktrees/w-NN
        git -C <wt> submodule update --init --recursive   (if .gitmodules)
   jj:  jj workspace add --name w-NN .claude/worktrees/w-NN
4. link the list
5. warn if the parent working copy is dirty — the worktree is based on @-/HEAD,
   so in-progress edits are NOT there
6. print the target dir: <wt>/<cwd relative to repo root>, falling back to <wt>
   and saying so when that subdir does not exist there (untracked dirs do not
   come across)
```

If step 3 or 4 fails, release the slot and exit nonzero **without** a hold —
there is nothing to preserve.

## Reap

Runs at wrapper launch (piggybacked, like `ccjj prune`) and via
`cc-worktree reap [--all]`. Enumerates the **union** of `w-*.owner` files, `w-*`
directories, and registrations under `<wt>/` from `git worktree list --porcelain`
/ `jj workspace list` — so no state that exists in only one of the three is
invisible. `git worktree list --porcelain` is captured **once at the top** and
carried through: step 3 destroys the registration that step 4 needs the branch
from, and the `missing .owner` row never had one. Orphaned branches make every
later `create` take the `w-NN-<stamp>` fallback forever.

Takes the same `flock` pattern `ccjj` uses: two `cc` launches racing means one's
`git worktree prune` can drop a registration the other's `git worktree add` is
mid-way through creating (verified: prune has no expire grace).

| `.owner` | dir | `.hold` | Action |
|---|---|---|---|
| alive | — | — | leave |
| dead | exists | **yes** | **skip, name it on stdout** with the `release --force` line |
| dead | exists | no, **but dirty** | **write `.hold "uncommitted (crashed)"`, name it.** SIGKILL / `Cmd+Q` / `tmux kill-session` all skip the exit path, so this IS the crash case — trashing here loses the only copy. |
| dead | exists | no, clean | recover-and-release |
| dead | missing | — | unregister, unlink `.owner` (crash mid-release) |
| missing | exists | — | treat as dead → recover-and-release |
| missing | missing | — | unregister only (stale registration) |

recover-and-release, **in this order** — each step leaves a state a re-run
finishes, which is what makes an interrupt anywhere non-destructive:

```
1. jj only:  jj bookmark set w-NN-<YYYYmmdd-HHMM> -r 'w-NN@'
             costs nothing, and after `forget` the working-copy commit is not in
             the default revset. Runs from the PARENT — never enter the workspace.
2. trash <wt>/w-NN                     work is now recoverable from the trash.
                                       A NONZERO trash ABORTS the release with
                                       .owner intact -- continuing would leave a
                                       non-empty dir at the slot path, which
                                       `git worktree add` then rejects forever.
3. unregister:  git: git worktree prune        jj: jj workspace forget w-NN
4. git only:  git branch -d <branch>   -d, not -D. Refusal ⇒ report the name;
                                       the branch IS the recovery handle.
5. rm <wt>/w-NN.owner                  LAST. While it exists the slot is claimed,
                                       so any earlier interrupt is re-processed.
6. trash $XDG_STATE_HOME/cc-jj-journal/<worktree-path-key>/  (if present)
```

Removing `.owner` first would orphan every remaining step. Trashing before
unregistering is safe because both `git worktree prune` and `jj workspace forget`
are exactly the "registered but gone" cleaners, and both are idempotent.

Anything skipped is **named on stdout, never silently** — the `ccjj` convention.

`reap --all` iterates `$XDG_STATE_HOME/cc-worktree/repos`, dropping lines whose
marker no longer exists.

## Exit path

After `claude` returns, the wrapper `cd`s back to the original directory, then:

```
git:
  wt dirty (git -C <wt> status --porcelain non-empty)?  -> HOLD "uncommitted"
  git -C <repo-root> merge --no-edit <branch>
    clean     -> release (reaper's recover-and-release, minus the jj step)
    conflict  -> git -C <repo-root> merge --abort
                 HOLD "merge conflict on <branch>"
                 print: the branch name, and `git merge <branch>` to retry
    "local changes would be overwritten" -> do NOT --abort (exits 128, there is
                 no merge in progress). HOLD, and print:
                   git stash && git merge <branch> && git stash pop
    other err -> merge --abort (best effort), HOLD with the git message
  parent branch != .owner.parent_branch? -> HOLD "parent moved to <X>", name both

jj:
  jj -R <wt> st                                     snapshot FIRST -- the parent
                                                    otherwise sees only what the
                                                    workspace last snapshotted
  jj bookmark set w-NN-<stamp> -r 'w-NN@'           always, next
  jj log --no-graph -r 'w-NN@' -T empty == "false"  -> HOLD "uncommitted"
    (--no-graph is mandatory: without it the output is "@  false" plus graph
     lines and the comparison can never match, so this branch always released)
  else release
```

A hold writes `w-NN.hold` (reason + branch/bookmark) and leaves everything in
place. `cc-worktree status` lists holds; `cc-worktree release w-NN --force`
clears one. Nothing else in the system ever reaps a held slot.

jj needs no merge: bookmarks are repo-global, so the agent's own
`jj commit` + `jj bookmark set master -r @-` inside the workspace already
advanced master.

**When every slot is held**, `create` fails, prints the held slots with their
reasons and the exact `cc-worktree release` lines, and the wrapper **runs
un-isolated, loudly**. Aborting the launch is hostile; isolating silently-not is
the failure this design exists to prevent.

## Wrapper changes

`fish/functions/my-claude-code-wrapper.fish`, against the current file.

| Current | Change |
|---|---|
| 1–15 (argv split) | unchanged |
| **60–71** (`skip_extras`) | **MOVE to line 16**, immediately after the argv loop. It depends only on `$pass_argv`; nothing between 15 and 60 sets it. The isolation block needs it. |
| — | **NEW isolation block** after the moved `skip_extras`. Sketch below. |
| 17–42 (`cc-config sync`) | unchanged text — but now runs **post-cd**, so it syncs into the worktree and writes the worktree's own `.claude/.cc-sync-stamp`. That is the point. |
| 44–51 (keychain) | unchanged |
| **54** `set -l label (basename (pwd))` | → `set -l label (basename (_cc_worktree_key))`, and append the slot when isolated: `set label "$label $_cc_wt_slot"`. Otherwise every session reads `w-01` in Activity Monitor. |
| **77** `sessions_dir` | unchanged text; **must stay after the cd**, because Claude Code derives its project dir from the real cwd. Add a comment saying so — this is the exact no-op its existing comment records having been burned by. |
| 89 `_ccs_open_register $fish_pid` | unchanged; `_ccs_key` inside `ccs.fish` does the work |
| 92 `proc-label … claude` | unchanged |
| — | **NEW after 92**: `cd $_cc_orig_pwd`, then the exit path above |
| **114** `set -l _ccs_dir "$HOME/Cloud/cc-sessions"(pwd)` | → `(_ccs_key)` |
| 128 `_ccs_open_finalize` | unchanged |

```fish
# --- isolation (sketch; run /fish before writing this for real) ---
set -l _cc_orig_pwd $PWD
set -l _cc_wt_slot ""
# Slot-aware resume: --resume/-c must land in the SAME directory the session ran
# in, or Claude Code cannot find its transcript. See "Slot-aware resume".
set -l _cc_resume_slot
if set -l sid (__cc_resume_id $pass_argv)
    set -l s (cc-worktree slot-for-session $sid)
    and set _cc_resume_slot --slot $s --reuse
end
if test $skip_extras -eq 0
    # NO 2>&1: create prints warnings on the SUCCESS path (dirty parent, subdir
    # fallback, submodules). Folding them in makes $target a multi-element list,
    # `cd` fails with "Too many args", and $status is STILL 0 -- so the wrapper
    # would run un-isolated with the slot claimed. Path on stdout, warnings on
    # stderr, and index the last element defensively.
    set -l target (cc-worktree create --pid $fish_pid $_cc_resume_slot)
    switch $status
        case 0
            set _cc_wt_slot (cc-worktree current --path $target[-1])
            cd $target[-1]
        case 2
            # no marker: nothing to do
        case '*'
            echo $target
    end
end
```

Exit code 2 for "not opted in" keeps the common case one process and zero output.
`create` itself must make **no `git`/`jj` call at all** when the marker is absent —
that is a test.

`skip_extras` gating is load-bearing: `ai.fish`, `ai_health`, `ai_inbox`, `ccpu`
and `sanctuary/main-claude` all route through this wrapper with `-p`, and would
otherwise leak a worktree per run *and* get an empty checkout to inspect.

## Slot-aware resume

**The problem, proven:** `claude --resume <id>` is scoped to the project
directory. Claude Code keys transcripts by mangled cwd
(`~/.claude/projects/-Users-anthony-proj` vs
`-Users-anthony-proj--claude-worktrees-w-01`). A session that ran in `w-01` and is
resumed from the parent gets `No conversation found with session ID`. `-c` /
`--continue` ("most recent conversation in the current directory") breaks the same
way, per slot. Since `--resume` is the entire reason `ccs`, `ccs-title-hook`,
`ccsave-hook` and `_ccs_restore_transcript` exist, isolation without this fix
breaks crash recovery — the thing it is supposed to protect.

**The fix is one property: the slot determines the path, so reusing the slot
restores resumability.** The transcript lives in `~/.claude/projects/`, not in the
worktree, so recreating the worktree at the same path is sufficient — the tree
itself need not have survived.

| Piece | Change |
|---|---|
| `.owner` | already carries `slot` |
| `_ccs_open_register` | writes `slot` into the ccs entry file alongside `cwd` |
| `cc-worktree slot-for-session <sid>` | reads the entry, prints the slot, exit 1 if none |
| `cc-worktree create --slot w-NN --reuse` | claims **that** slot specifically rather than the lowest free one, and recreates the worktree at the same path. Fails loudly if the slot is claimed by a *live* owner. |
| wrapper | detects `--resume/-r/-c/--continue` in `$pass_argv`, looks up the slot, passes `--slot … --reuse` |
| `ccs resume` (`ccs.fish:578/581`) | unchanged — it already calls the wrapper, which now does the right thing |

A resumed session whose slot cannot be determined (no recorded slot: an entry
predating this feature) runs **un-isolated and says so**. That is correct: the
transcript is keyed to the parent, so the parent is where it resumes.

`__cc_resume_id` is a pure-fish argv scan for `--resume <id>` / `-r <id>`;
for bare `-c`/`--continue` there is no id, so the slot cannot be looked up and the
session runs un-isolated, loudly. Documented limitation, not a silent one.

## Landing a hold

A hold is the **normal** end of a session, not an exception — most end with
uncommitted edits. Without a way to land one, ten uncommitted exits from a single
terminal exhaust `MAX_SLOTS`, and the only documented escape (`release --force`)
discards the work.

```
cc-worktree land w-NN     git: git -C <wt> stash create  -> apply into the parent
                               (or, with --commit, commit `wip: w-NN` on the branch
                                and merge it), then release
                          jj:  the bookmark already holds it -> release
cc-worktree release w-NN --land       land, then release
cc-worktree release w-NN --discard    trash it; the ONLY path that loses work
```

`release` with neither flag **refuses** and prints both. `--force` is removed as a
name: it was ambiguous between "clear the marker" and "discard the work".

## `ccs` re-keying

New autoloaded `fish/functions/_cc_worktree_key.fish` — verified working:

```fish
function _cc_worktree_key --description 'Session key: parent repo path for a cc worktree, else pwd'
    set -l p $argv[1]
    # $PWD (logical), NOT `pwd -P`: every ccs site this replaces uses logical
    # pwd, and /tmp -> /private/tmp and ~/Cloud (a ProtonDrive symlink) diverge,
    # which would silently orphan existing entries.
    test -n "$p"; or set p $PWD
    set -l m (string match -r '^(.*)/\.claude/worktrees/w-[0-9]+(/.*)?$' -- $p)
    if test (count $m) -ge 2
        printf '%s%s\n' $m[2] $m[3]
    else
        printf '%s\n' $p
    end
end
```

`/r/proj/.claude/worktrees/w-01` → `/r/proj`;
`…/w-07/src/app` → `/r/proj/src/app`; anything else unchanged. Note the fish
capture gotcha: when group 2 does not participate, `count $m` is **2**, not 3, and
`$m[3]` is empty — which `printf '%s%s'` handles correctly. Pure fish, no
subprocess, because it runs on every `cd` through `chpwd` → `_ccs_open_scan`.

In `ccs.fish`, replace `(pwd)` with `(_cc_worktree_key)` at exactly these sites:

| Line | Function | Effect if missed |
|---|---|---|
| 2 | `_ccs_file` | one `~/Cloud/cc-sessions/<path>` tree per worktree, forever |
| 592 | `_ccs_backup_session` | backups scattered per slot |
| 713 | `_ccs_open_register` | `ccs list` at the repo root shows nothing. **Also writes `slot`** — see "Slot-aware resume". |
| 993 | `_ccs_open_scan` (`want_cwd` arg) | live sessions invisible from the parent |
| 1167 | `_ccs_old` | archived sessions invisible |

Leave alone: `_ccs_migrate` (1206) reads legacy in-repo paths, and `_ccs_prune`
(1105, 1111) / `_ccs_restore_transcript` (683) read `.cwd` from the entry file,
which is now written with the key and is therefore already consistent.

Outside a worktree the key is `pwd`, so this whole change is a no-op — which is
why it can ship before the wrapper change and be verified on its own.

## `chpwd` surfacing

Next to the pending-updates block (`chpwd.fish:69`), one cheap fish-only check —
no subprocess, since this runs on every `cd`:

```fish
set -l _held .claude/worktrees/*.hold
if test (count $_held) -gt 0; and test -e $_held[1]
    # golden/orange, same treatment as pending-updates
end
```

Held slots only. Active slots are normal and not worth a line.

## Build sequence

Each step ships and is testable on its own.

| # | Step | Ships |
|---|---|---|
| 1 | `lib/python/cc_worktree.py` + `bin/cc-worktree`: `on` / `off` / `status`, marker parsing, link-list validation, registry. No behaviour change anywhere else. | You can opt a repo in and see status. |
| 2 | `create` / `release` / `reap`, both backends, trash-based, with `.hold`. Driven by hand. | `cc-worktree create` gives a worktree you `cd` into yourself; `reap` cleans up. Tests 1–18 land here. |
| 3 | `_cc_worktree_key.fish` + the five `ccs.fish` re-keys. | No-op outside worktrees; verify `ccs list` / `ccs old` still behave normally. **Must precede step 4** or `ccs` breaks the instant isolation lands. |
| 4 | Wrapper: move `skip_extras`, add the isolation block, fix `label`, comment `sessions_dir`. | Isolation live on launch. |
| 5 | Wrapper exit path: cd back, merge, hold, release. `_ccs_dir` → `_ccs_key`. | Round trip closed. |
| 6 | `reap --all`, `chpwd` surfacing, `docs/cc-worktree.md`. | Housekeeping visible. |

## Tests

`cmds test` from the dotfiles root — never bare pytest. Both target directories
are already registered components (`lib/python`, `fish`), so no `run_tests.py`
change is needed. Each test names the defect it pins.

### `tests/lib/python/test_cc_worktree.py`

| Test | Defect pinned |
|---|---|
| `slot_race_two_claimers` | check-then-create TOCTOU → two sessions in one worktree, the exact thing this design exists to prevent |
| `claim_survives_kill_before_create` | a claimed-but-empty slot leaking forever |
| `dir_without_owner_is_reaped` | a tree no reaper enumerates (crash between create and claim, or a hand-deleted `.owner`) |
| `pid_alive_lstart_differs_is_dead` | pid recycling leaves a live-looking dead slot forever |
| `reap_trashes_ignored_env_file` (both backends) | **draft one's killer**: `git worktree remove` returns 0 and deletes `.env` |
| `reap_is_idempotent_after_interrupt` | half-released slot wedges allocation; asserts a second reap completes step 3–5 |
| `held_slot_never_reaped_and_named` | reaping unmerged work; asserts the name reaches stdout |
| `unmerged_branch_survives_release` | the baseline's `git branch -D` destroying the commits the reaper just preserved |
| `jj_bookmark_set_before_forget` | verified fact — after `forget` the working-copy commit leaves the default revset |
| `jj_unsnapshotted_file_only_in_trash` | over-claiming that the bookmark recovers everything; the parent sees only the last snapshot |
| `nesting_refused_git` / `nesting_refused_jj` | recursive worktrees; asserts `--git-dir` ≠ `--git-common-dir` and `.jj/repo` is a file |
| `marker_found_when_dot_git_is_a_file` | `.git/cc-worktree` silently no-ops in a submodule or linked worktree → isolation quietly does not happen |
| `on_refuses_dotfiles` | opting in a repo that cannot be isolated |
| `on_refuses_untracked_link_entry_in_jj` | jj auto-tracks a symlinked `node_modules` and commits a link into the parent |
| `link_list_resolves_in_worktree` | draft one's defect 2: `.cc-config`/`.claude` absent → `cc-config sync` no-ops → unconfigured session, silently |
| `all_slots_held_fails_loudly` | silently running un-isolated when the pool is exhausted |
| `missing_subdir_falls_back_to_root` | `cd` into a path that does not exist in the worktree (untracked dirs do not come across) aborting the launch |
| `release_removes_ccjj_journal_namespace` | an unprunable `cc-jj-journal/<path>/` namespace per worktree, forever |

### `tests/fish/test_cc_worktree_wrapper.py` (pytest driving `fish -c`)

| Test | Defect pinned |
|---|---|
| `key_maps_worktree_subdir_and_passthrough` | `ccs list` empty inside a worktree; a non-slot `.claude/worktrees/foo` wrongly rewritten |
| `skip_extras_creates_nothing` | headless `-p` callers leaking a worktree per run and inspecting an empty checkout |
| `no_marker_runs_no_vcs_command` | a cost and a regression surface on every non-opted-in repo; assert via a PATH shim that records `git`/`jj` calls |
| `label_is_parent_basename_plus_slot` | every session showing as `w-01` in Activity Monitor |
| `sessions_dir_computed_after_cd` | the post-session review silently no-opping — the bug the existing comment at line 73 records |
| `relaunch_same_shell_gets_two_slots` | `$fish_pid` is stable → `fatal: branch 'cc-111' already exists` |
| `exit_merges_clean_and_releases` | the round trip: commit in the worktree, exit, parent master has it, branch gone, slot free |
| `exit_conflict_aborts_and_holds` | a conflicted merge left half-applied, or the branch trashed by a later reaper |
| `parent_dirty_warns_and_base_is_parent_commit` | "help me finish this edit" silently starting from `@-`/HEAD without those edits |

## Not doing

- **A merge queue.** Disproved as necessary.
- **Automatic conflict resolution.** Abort, hold, name the branch, stop.
- **Isolating `~/dotfiles`.** `on` refuses. `ccjj` owns that case.
- **Covering entry points other than the `cc` abbr.** Bare `claude`, the IDE
  extensions, the desktop app and any direct `claude -p` all bypass the wrapper,
  so a repo can hold one isolated and one non-isolated session at once. Document
  it; do not oversell it.
- **Making `ccjj` worktree-aware.** It already self-disables correctly in a
  workspace (own `.jj` → own repo key → no peers → whole-copy commit, which is
  *better* there). Only its journal namespace needs cleaning up, which the reaper
  does.
- **`WorktreeCreate`/`WorktreeRemove` hooks** so the built-in `EnterWorktree` also
  works in jj repos. Later, if wanted.
- **Pre-trusting new cwds in `~/.claude.json`.** One trust dialog per slot per
  repo on first use, bounded at `MAX_SLOTS` by reuse. Editing that file is not
  worth the blast radius.
- **Submodules beyond `git submodule update --init --recursive`.** jj has no
  equivalent; `on` warns.
- **Ever editing `~/.claude/settings.json`** — same inode as
  `rcs/claude-settings.json`, and a hook blocks it. Nothing here needs a hook
  anyway.

## Accepted risks

| Risk | Status |
|---|---|
| A `svc` dev server or editor holds files in the worktree | trash-not-delete makes it recoverable; noted in the doc |
| A jj session's post-last-snapshot edits are not in the bookmark | true and unavoidable — the parent cannot snapshot another workspace. The trash is the recovery path; the doc says so |
| A crashed shell's slot is not reaped until that shell exits | conservative direction: the work stays on disk |
| A repo you stop visiting keeps its worktrees | `reap --all` + `chpwd` surfacing of holds |
| Link-list symlinks mean two sessions share `node_modules` / `.venv` | deliberate — that is the point. A repo needing divergence uses `copy:` |
