# `WorktreeCreate` / `WorktreeRemove` for jj repos — implementation plan

Claude Code 2.1.220 ships `--worktree` natively. In a colocated jj repo it
produces a **git** worktree with no `.jj`, so `jj` inside it walks up and resolves
to the **parent** — an agent obeying "use jj for all VCS operations" then commits
another session's in-flight work while its own lives only on a git branch.

The fix is a hook pair that creates a **colocated jj workspace** instead. That
retires all of `cc-worktree`'s machinery: the native feature already owns naming,
creation, resume, the exit prompt and cleanup triggering, which was ~80% of it,
and the rest (slots, holds, merge-back, the reaper, `ccs` re-keying) exists only
to serve the parts it replaces — §10.

What survives on our side is small and has two halves:

| | |
|---|---|
| **the hook pair** — always on, every repo | makes the worktree a real jj workspace, and reimplements the four native post-create steps CC skips when a hook is configured |
| **~12 lines in the `cc` wrapper** — gated by a per-checkout marker | appends `--worktree` so the user never types it; `cc --no-worktree` opts out. It creates nothing, `cd`s nowhere, tracks nothing. §6 |

---

## 1. Corrections to the brief

Everything here was read out of `~/.local/share/claude/versions/2.1.220` (the JS
is recoverable with `perl -0777 -ne 'while(/…/sg){print "$&"}'`) or reproduced on
this machine today. Four items contradict the brief and one contradicts the
public docs page.

| Brief said | Actually |
|---|---|
| `WorktreeCreate` stdin has `worktree_name`, `worktree_base_path` | **`name`** — the suggested slug — and nothing else worktree-specific. `LPt(e){let t={...Kf(void 0),hook_event_name:"WorktreeCreate",name:e}}`. The public docs page's `worktree_path`/`source_path` is also wrong. `Kf` supplies `session_id`, `transcript_path`, `cwd`, `prompt_id`, `permission_mode`, `agent_id`, `agent_type`, `effort`. |
| the hook "must print the absolute path … on stdout" | true, but the reader is `DFy = last non-empty trimmed line of stdout`. On **exit 0 the hook's stderr is discarded entirely** (`output = status===0 ? stdout : stderr`), so a success-path warning reaches nobody. Warnings go to a log file. |
| `WorktreeRemove` "exit code and output ignored" | **The exit code is load-bearing.** `Xor()` returns true iff a hook exited 0. Exit 0 ⇒ CC stops. Exit **nonzero** ⇒ CC logs `WorktreeRemove hook did not remove worktree, kept at:` and **does not** run its git fallback. So nonzero is a usable "I kept it" signal. |
| the hook must "no-op, delegating to native git behaviour" where unwanted | **There is no delegation.** `if(hasWorktreeCreateHook())` replaces the whole creation branch. A globally-registered hook is fully responsible for creation in **every** repo, plain git included. |
| — | **If a `WorktreeCreate` hook is registered without a `WorktreeRemove` hook, CC falls back to `git worktree remove --force` on our path** (`No WorktreeRemove hook configured; falling back to git worktree remove for:`). That deletes ignored files. Registering the pair is not optional. |

The brief's claim that `.worktreeinclude` is skipped is **confirmed**, and it is
worse than stated: the whole post-create step `dcs()` is skipped, which is *four*
native features, not one — see §3.4.

---

## 2. Verified facts

Reproduced today in `$scratchpad/wt1`–`wt4` (jj 0.39.0, git 2.39.5, CC 2.1.220).
Do not re-derive.

| Fact | Consequence |
|---|---|
| `jj workspace add <p>` → `.jj/repo` is a **file** holding a **relative** path; `jj root` inside = the workspace | this is the whole fix |
| but `git rev-parse --show-toplevel` inside a bare workspace = the **PARENT** | jj-only is the mirror of the bug we are fixing, not a fix |
| `git worktree add <p>` then `jj workspace add <p>` → `Error: Destination path exists and is not an empty directory` (**even when `<p>` holds only `.git`** from `--no-checkout`) | the two cannot be composed directly, in either order |
| `jj workspace add <final>`; `git worktree add --no-checkout -b B <stage>/<name> <base>`; `mv <stage>/<name>/.git <final>/.git`; `git worktree repair <final>`; `git -C <final> reset --mixed -q HEAD` | **works.** `jj root` and `git rev-parse --show-toplevel` both = the worktree; `jj st` and `git status --porcelain` both clean; both registries list it. One checkout total (`--no-checkout` writes only `.git`). |
| without the `reset --mixed`, `git status` shows every file `D` + `??` | the index from `--no-checkout` is empty |
| `git worktree repair` fixes the `gitdir` back-link after the move | no hand-written back-link file |
| the parent's `jj st` does **not** see files inside a nested workspace — even with `core.excludesFile=/dev/null` | jj skips nested workspaces structurally. The "parent auto-tracks the worktree" hazard **does not exist**. (git *does* show `?? .claude/`.) |
| a file created in the workspace appears in the *workspace's* `jj st` as a workspace-relative path | paths are correct on both sides |
| `jj workspace add` fails `Cannot access …` unless the destination's **parent directory exists** | `mkdir -p .claude/worktrees` first |
| `jj bookmark set X -r '<ws>@'` before any snapshot ⇒ `Warning: Target revision is empty` and the bookmark misses the work | **`jj -R <wt> st` first**, always |
| after the snapshot, `jj log --no-graph --ignore-working-copy -r '<ws>@' -T empty` prints `false` | `--no-graph` is mandatory; `--ignore-working-copy` stops the read snapshotting the *parent* |
| `jj workspace forget <name>` on a **dirty** workspace: rc 0, leaves the directory | it will not protect you |
| after `forget` the working-copy commit is not in the default revset (reachable only via the bookmark) | bookmark **before** forget |
| CC runs `git -C <worktreePath> status --porcelain` and `rev-list --count ..HEAD` for the exit prompt (*"You have N uncommitted files… All will be lost if you remove"*) | in a jj-only workspace that reports the **parent's** dirt, at the moment of a destructive choice |
| `EnterWorktree` on an existing worktree requires a `.git` file, a `.git/worktrees/<id>/gitdir` back-link, registration in `git worktree list`, and a location under `<repo>/.claude/worktrees/` | a jj-only workspace can never be re-entered |
| hook-based worktrees skip `qDu()` (the `git worktree lock --reason "claude <pid> start <t>"` step) | CC does not lock ours; we take our own `flock` |
| hook `timeout` in settings.json is **seconds** (`_.timeout ? _.timeout*1000 : default`) | the `5000`/`10000` entries in `rcs/claude-settings.json` were 83 and 166 **minutes**; corrected to `5`/`10` while this plan was being written. Use seconds. |
| `getGitWorktreeName` derives the worktree name from `.git/worktrees/<id>` and returns `null` when there is no `.git` | a jj-only worktree has no name as far as CC is concerned — one more reason the colocated attach is not cosmetic |
| the emitted path must be absolute, contain no `.`/`..` segments, have no symlinked component below the checkout root, and be an existing **directory** at exit | four separate hard failures with distinct messages |
| a path **outside** the repository is accepted and skips the symlink screen | an escape hatch we deliberately do not take (§3.2) |

---

## 3. Decisions

### 3.1 Does the hook create a jj workspace, and who creates what?

**The hook creates everything. CC creates nothing.** Confirmed in the binary.
So the hook is a full replacement for native creation in every repo it fires in,
and "make jj work" and "do not regress git" are the same job.

**Colocated jj repos get a colocated workspace** — jj workspace *and* an attached
git worktree, by the sequence in §2. Reasons, in order of weight:

1. A bare jj workspace fixes `jj` and breaks `git` symmetrically. The parent repo
   is colocated; the child must be too or one of the two tools silently addresses
   the parent.
2. CC itself runs `git -C <wt> status --porcelain` to populate the keep/remove
   prompt. Wrong there means the user is told the wrong thing at the one moment
   the answer destroys something.
3. `EnterWorktree` on an existing worktree hard-requires the git registration.
4. `git branch -d worktree-<name>` refusing on unmerged work is the recovery
   handle the retiring design proved worth keeping.

The git attach is **best-effort**: if any of its four steps fails, log it, keep
the jj workspace, and return its path anyway. The primary defect is fixed either
way, and failing creation over a degraded-but-correct worktree is worse.

### 3.2 Colocated vs non-colocated jj vs plain git

Backend is detected without forking anything (`cc_worktree.find_repo`, kept):

| `.jj` | `.git` | Mode | Create | Remove |
|---|---|---|---|---|
| yes | yes | **colocated** | `jj workspace add` + git attach | snapshot → bookmark → trash → `jj workspace forget` → `git worktree prune` → `git branch -d` |
| yes | no | **jj-only** | `jj workspace add` | snapshot → bookmark → trash → `jj workspace forget` |
| no | yes | **git** | `git worktree add -b worktree-<name> <path> <base>` | trash → `git worktree prune` → `git branch -d` |
| no | no | — | exit 1, echoing CC's own wording | exit 0, nothing to do |

`.git` is tested with `os.path.exists`, not `isdir` — it is a *file* in a linked
worktree and in a submodule.

The worktree goes at `<repo>/.claude/worktrees/<name>`, the native location, even
though emitting a path outside the repo would skip CC's symlink screen. Outside
means `EnterWorktree` can never find it (`requireManagedLocation`), and the
`.claude/` prefix is what makes the tree invisible to the parent's *git* under
`gitignore_global:2` (`.*`).

**Nesting is refused** (`cc_worktree.nested_reason`, kept): `.jj/repo` is a file
in a workspace, and `--git-dir` ≠ `--git-common-dir` in a linked worktree. The
retiring plan's finding stands — from inside a worktree the parent's markers are
still reachable, so nothing else stops `w/.claude/worktrees/w2`.

**`~/dotfiles` is refused** (exit 1), naming `ccjj` / `commit-mine`. ~46% of its
tracked files load by absolute path, so a worktree copy can author changes it
cannot run. A refusal from `WorktreeCreate` puts our stderr in front of the user,
which is the loud outcome; `CC_WORKTREE_FORCE=1` overrides.

### 3.3 What `WorktreeRemove` does

It fires at session exit (**after** the user has already answered CC's own
`Keep worktree` / `Remove worktree` prompt, which reports the uncommitted count),
and on subagent completion, where there is no prompt at all.

**No hold state machine.** The retiring design's `.hold` / `land` / `release`
apparatus existed because nothing else asked the question; CC now asks it. So:

```
1. jj: jj -R <wt> st                       # snapshot FIRST or the bookmark is empty
2. jj: jj bookmark set cc/<name>/<YYYYmmdd-HHMM> -r '<name>@'
3.     trash <wt>                          # NEVER `git worktree remove`
4. jj: jj workspace forget <name>          # idempotent, rc 0 on unknown names
5. git: git worktree prune                 # idempotent
6. git: git branch -d worktree-<name>      # -d, never -D
7. exit 0
```

Ordering is the retiring design's, unchanged, and every step leaves a state a
re-run finishes. Deviations from it:

- **A nonzero `trash` exits nonzero**, so CC logs `did not remove worktree, kept
  at:` and skips its `git worktree remove --force` fallback. Continuing would
  leave a non-empty directory where a later `git worktree add` fails forever.
- Nothing is ever `rm`'d. `trash` (§CLAUDE.md) makes an unwise "Remove" answer
  recoverable, and the bookmark makes the snapshotted half recoverable in-repo.
- **Path guard before anything destructive.** `worktree_path` is attacker-shaped
  input as far as this script is concerned: it must be absolute, exist, be a
  directory, its `realpath` must be strictly under `realpath(<repo>/.claude/
  worktrees)`, its parent must be named `worktrees` under a `.claude`, and it
  must not equal or contain the repo root or `$PWD`. The repo root is derived
  from the **path itself**, not from `cwd` — CC chdirs back to `originalCwd`
  before calling us but *logs and continues* if that chdir fails.
- A `worktree_path` we did not create (pre-hook, or a plain git worktree) is
  handled by the same code: `jj workspace list` simply will not name it, and the
  jj steps no-op.

### 3.4 Is opt-in still needed? (decided by amendment)

**Two different questions, two different answers.**

- **The hook is never gated.** It fires wherever `--worktree` / `isolation:
  "worktree"` is used, in every repo. Gating it would mean "isolation was asked
  for and the broken kind was silently supplied" — the failure this exists to
  remove.
- **The wrapper is gated by a per-checkout marker.** In an opted-in project the
  wrapper appends `--worktree` to argv so worktrees are always on without the
  user remembering the flag; `cc --no-worktree` opts out for one invocation. §6.

The wrapper's *only* job is that argv decision. It creates nothing, `cd`s
nowhere, and tracks nothing — Claude Code owns creation, resume, the exit prompt
and cleanup; the hook owns jj.

Because the hook is ungated it fires in every repo on this machine, so it must
reimplement what `dcs()` does natively and is skipped for hook-based worktrees.
All four, or registering the hook is a silent regression for plain git repos that
never wanted any of this:

| Native step | Hook must |
|---|---|
| `worktree.symlinkDirectories` (settings.json) | symlink each named dir from the parent. Same escape guard CC has (`destination escapes worktree via committed symlink`) and that `link_one` learned by deleting real files. |
| `.worktreeinclude` | copy matching ignored/untracked paths. `git -C <root> ls-files -z --others --ignored --exclude-from=.worktreeinclude` does the pattern matching, no matcher to reimplement. (Superset of CC's two-pass version, which intersects with `--exclude-standard`; a listed *non*-ignored untracked file gets copied by ours and not by CC's. Harmless, documented.) |
| `core.hooksPath` | `git -C <wt> config core.hooksPath <abs>` when the main repo sets one |
| `worktree.sparsePaths` | `git -C <wt> sparse-checkout set --cone <paths>` |

`worktree.baseRef` (`fresh` = `origin/<default-branch>`, the **native default**;
`head` = local HEAD) is honoured too — see step 5.

Settings are merged, low to high, from `~/.claude/settings.json`,
`<repo>/.claude/settings.json`, `<repo>/.claude/settings.local.json`. Arrays
concatenate and dedupe. Policy/managed settings are not read; note it in the doc.

---

## 4. Files

| Path | Change |
|---|---|
| `lib/python/cc_worktree.py` | **rewritten in place.** ~1400 → ~450 lines. Subcommands: `hook-create`, `hook-remove`, `should-isolate`, `on`, `off`, `status`. Kept: `find_repo`, `git_dir`, `git_common_dir`, `marker_path`, `nested_reason`, `dotfiles_root`, `run`/`die`/`warn`, `acquire_lock`, `trash`, `link_one`/`link_all`, `jj_workspaces`, `unregister`, `stamp`. Gone: everything in §10. |
| `bin/cc-worktree` | unchanged two-line shim |
| `rcs/claude-settings.json` | register the pair — §7 |
| `docs/cc-worktree.md` | rewritten around the native feature |
| `tests/lib/python/test_cc_worktree.py` | rewritten — §9. Also carries the wrapper argv tests, driving `fish -c`, because `tests/fish/` never executes. |
| `fish/functions/my-claude-code-wrapper.fish` | delete the isolation block (30–101) and the exit path (179–187); revert `label` (140–146) to `basename (pwd)`; add the ~12-line argv decision of §6 |
| `fish/functions/ccs.fish` | revert 6, 598, 1016, 1190 to `(pwd)`; drop `slot` from `_ccs_open_register` (720–762) and the read at 834 |
| `fish/functions/chpwd.fish` | delete `showHeldWorktrees` (76–86) and its call (141) |
| `fish/functions/_cc_worktree_key.fish`, `_cc_worktree_slot.fish`, `__cc_resume_id.fish`, `__cc_resume_requested.fish` | trash |
| `.gitignore` | drop negations 33–36 |
| `tests/fish/test_cc_worktree_wrapper.py` | trash (and it never ran — `cmds test` only runs `lib/python`) |

Python, not fish, for the same reason `ccjj` is: the ordering rules are the hard
part and they need real tests.

**REQUIRED: run the `/fish` skill before touching any `.fish` file.** Three of
them are in the retirement list. Repo rule, no exceptions.

---

## 5. `cc-worktree hook-create`

Reads the JSON payload on stdin. Prints **one line — the path — on stdout, and
nothing else ever**. Diagnostics go to `$XDG_STATE_HOME/cc-worktree/hook.log`,
because CC discards stderr on exit 0. stderr is used **only** on the exit-1 path,
where it becomes the user-visible failure message.

```
 0. name = payload["name"]; refuse unless ^[A-Za-z0-9][A-Za-z0-9._-]{0,59}$
       and name not in (".", ".."). REFUSE, never sanitise: CC keys an existing
       worktree by directory BASENAME (_cs builds {basename: {path, branch}}),
       so a mangled name is a worktree EnterWorktree can never find again.
 1. root, backend = find_repo(payload["cwd"])   # no subprocess
       none            -> exit 1, CC's own wording about other VCS systems
       root == dotfiles_root() and not $CC_WORKTREE_FORCE -> exit 1, name ccjj
       nested_reason() -> exit 1
 2. wt = root/.claude/worktrees/name ; mkdir -p its parent (jj REQUIRES this)
       refuse if .claude/worktrees is a symlink (CC refuses it later anyway)
 3. flock(root/.claude/worktrees/.lock, 30s deadline)      # ccjj's shape
 4. if wt already exists and is a live worktree/workspace: ADOPT it, jump to 7.
       CC's native path resumes an existing worktree by name; and the hook
       timeout can kill us mid-build, so re-running must converge.
 5. create:
      jj:  jj workspace add --name <name> <wt> [-r <base>]
      git: git worktree add -b worktree-<name> <wt> <base>
           git -C <wt> submodule update --init --recursive   (if .gitmodules)
 6. colocated only, best-effort — log and continue on any failure:
      base  = jj log --no-graph --ignore-working-copy -r '<name>@-' -T commit_id
      stage = mkdtemp(dir=root/.claude/worktrees, prefix=".stage-")
      git worktree add --no-checkout -b worktree-<name> <stage>/<name> <base>
          # path basename == name so the git worktree id == name
      mv <stage>/<name>/.git <wt>/.git ; rmdir -p <stage>
      git -C <root> worktree repair <wt>
      git -C <wt> reset --mixed -q HEAD      # index is EMPTY after --no-checkout
 7. post-create, the four things dcs() would have done (§3.4)
 8. print(wt)   # absolute, normalised, no dot segments
```

Failure between 5 and 7 tears down what it built (trash the tree, `jj workspace
forget`, `git worktree prune`, `git branch -d`) and exits 1. There is nothing to
preserve at that point, and leaving a half-built tree makes every later create at
that name fail.

Nothing here consults a marker to decide *whether* to act. `<repo>/.jj/cc-worktree`
(or `<git-common-dir>/cc-worktree`) is read only for overrides — extra symlink
entries, `base-ref`. Absent is the normal case.

---

## 6. The wrapper: append `--worktree`, and nothing else

`fish/functions/my-claude-code-wrapper.fish`. **Run the `/fish` skill before
writing this.** The whole change is an argv decision — no `cd`, no state, no
exit path.

### 6.1 The six questions

| # | Question | Answer |
|---|---|---|
| 1 | resume | **Never append on resume.** Verified in the binary: a resumed conversation carries a persisted `worktreeSession`, and its effective directory is `worktreeSession===void 0 ? projectPath : worktreeSession.worktreePath` — resume returns to the worktree by itself. There is also a `tengu_resume_worktree_fallback` path that scans worktree project dirs for `<sid>.jsonl`, which only exists because transcripts *are* keyed to the worktree cwd. `--worktree`'s only job is creation, so adding it as well would ask for a second one. **Untested end to end** — step 4's checklist covers it. Detect `--resume`, `--resume=…`, `-r`, `--continue`, `-c`. |
| 2 | `skip_extras` | **Never append.** Same load-bearing gate as before: `ai.fish`, `ai_health`, `ai_inbox`, `ccpu` and `sanctuary/main-claude` all route through this wrapper with `-p`. A worktree per headless run, and an empty checkout to inspect. |
| 3 | user already passed it | **Never append.** `-w`, `--worktree`, `--worktree=<name>`, and `--worktree <name>`. All four are the same check because `contains --` and `string match -q` both scan the whole list. |
| 4 | stripping `--no-worktree` | It is filtered in the **existing** argv loop (lines 6–15), alongside `--process-label`, so it never reaches `claude`, which does not know the flag. Fish notes: `set -a pass_argv $arg` keeps elements separate; append the flag as **two elements** (`set -a pass_argv --worktree $name`), never one string with a space; and pass `$pass_argv` unquoted at the call site, which line 177 already does. |
| 5 | the same project opened twice | **Each session gets its own worktree, and the wrapper generates the name rather than letting CC default it.** CC's `ucs()` has a `Resuming existing worktree at:` branch, so if its default name were ever stable, a second concurrent session would silently *share* the first's tree — the exact collision this feature exists to prevent, restored by the back door. Generating `cc-<HHMMSS>-<4 random>` in the wrapper makes non-collision a property of our code instead of a bet on undocumented behaviour, and the `cc-` prefix marks wrapper-created trees. Concurrency below that is already handled: the hook takes a per-repo `flock`, and jj and git each refuse a duplicate workspace/worktree name. |
| 6 | where the marker lives | **Unchanged: `<git-common-dir>/cc-worktree`, or `<repo>/.jj/cc-worktree`.** The original justification survives the reshape intact and is now *more* load-bearing, not less: `.git` is a file in a linked worktree and in a submodule, and the wrapper is now specifically expected to be run from **inside** a worktree (the user `cd`s into one to look at something). That is the case that must resolve to the parent's marker and then be refused for nesting. The path is per-checkout, never committed, and never synced to another machine. `cc-worktree on` / `off` / `status` keep managing it. |

The decision is not reimplemented in fish. **`cc-worktree should-isolate`** (exit
0 = yes) answers it, in the shape `ccjj should-scope` already established: it owns
marker lookup, the nesting refusal, the `~/dotfiles` refusal and backend
detection, in one place with tests. One ~50 ms process per interactive `cc`
launch is not worth duplicating tested logic to avoid.

### 6.2 Sketch

Against the current file. In the argv loop (6–15), add a third branch:

```fish
else if test "$arg" = --no-worktree
    set no_worktree 1          # swallowed: `claude` does not know this flag
```

with `set -l no_worktree 0` declared next to `process_label` at line 3. Then,
**replacing** the isolation block at 30–101:

```fish
# --- worktree isolation ------------------------------------------------
# In a checkout opted in with `cc-worktree on`, every session gets its own
# worktree. Claude Code does the work; this only decides the flag. The
# WorktreeCreate hook makes that worktree a real jj workspace in a jj repo —
# docs/cc-worktree.md.
#
# skip_extras is load-bearing: ai.fish, ai_health, ai_inbox, ccpu and
# sanctuary/main-claude all route through here with -p and would leak a
# worktree per run.
#
# NOT on resume: a resumed session already carries its worktreeSession and
# returns to its own worktree. Adding the flag would ask for a second one.
if test $skip_extras -eq 0; and test $no_worktree -eq 0
    set -l already 0
    if contains -- --worktree $pass_argv; or contains -- -w $pass_argv
        set already 1
    else if string match -q -- '--worktree=*' $pass_argv
        set already 1
    end
    set -l resuming 0
    if contains -- --resume $pass_argv; or contains -- -r $pass_argv
        set resuming 1
    else if contains -- --continue $pass_argv; or contains -- -c $pass_argv
        set resuming 1
    else if string match -q -- '--resume=*' $pass_argv
        set resuming 1
    end
    if test $already -eq 0; and test $resuming -eq 0
        # Our own name, not Claude Code's default: `ucs()` has a
        # "Resuming existing worktree" branch, so a stable default name would
        # put two concurrent sessions in ONE worktree — the collision this
        # feature exists to prevent.
        if cc-worktree should-isolate
            set -a pass_argv --worktree "cc-"(date +%H%M%S)"-"(random 1000 9999)
        end
    end
end
```

`set -a pass_argv --worktree <name>` appends **two** elements. Everything
downstream is unchanged: `label` reverts to `basename (pwd)`, `sessions_dir` and
`_ccs_open_register` use the launch directory (which no longer moves), and there
is no exit path at all.

## 7. Registration

`rcs/claude-settings.json` only. **Never `~/.claude/settings.json`** — same inode,
and `~/.claude/hooks/ensure-rcs.sh pre` blocks writes to it.

```json
"WorktreeCreate": [
  { "hooks": [ { "type": "command",
                 "command": "cc-worktree hook-create", "timeout": 300 } ] }
],
"WorktreeRemove": [
  { "hooks": [ { "type": "command",
                 "command": "cc-worktree hook-remove", "timeout": 120 } ] }
]
```

No `matcher` key — neither event supports one. `timeout` is **seconds**; 300 is
generous for `jj workspace add` on a large checkout and still bounded. Both must
land in the same edit: a create hook without a remove hook hands our path to
`git worktree remove --force`.

---

## 8. Build sequence

Each step ships and is verifiable alone.

| # | Step | Verify |
|---|---|---|
| 1 | `hook-create` for the **colocated jj** case only; other backends exit 1. Not registered yet. | `echo '{"name":"t1","cwd":"…"}' \| cc-worktree hook-create` in a scratch repo; then `jj root` and `git rev-parse --show-toplevel` inside both equal the worktree. |
| 2 | `hook-remove`, all three backends, with the path guard. Not registered yet. | drive it by hand against step 1's tree; assert the tree is in the trash, both registries are clean, and the bookmark holds the dirty file. |
| 3 | git-only and jj-only creation paths. | scratch repos of each shape. |
| 4 | **Register both in `rcs/claude-settings.json`.** | `claude --worktree jjtest` in a scratch colocated repo; inside, `jj root` is the worktree; exit and choose Remove; the tree is in the trash. Then the same in a plain git repo — behaviour must be indistinguishable from before registration. |
| 5 | `symlinkDirectories`, `.worktreeinclude`, `core.hooksPath`, `sparsePaths`, `baseRef`. | a repo with a `node_modules` and a `.worktreeinclude` gets both. **Until this lands, those five native settings are inert — a named regression, not a surprise.** |
| 6 | **Retire** `cc-worktree`'s old surface (§10): fish functions, wrapper block, `ccs` re-keys, `chpwd`. | `cmds test`; `ccs list` / `ccs old` unchanged; a plain `cc` in an un-opted-in repo behaves exactly as before. |
| 7 | `cc-worktree should-isolate` + `on`/`off`/`status` against the marker + the wrapper argv block (§6). | `cc-worktree on` in a scratch jj repo, then `cc` → a `cc-*` worktree appears and `jj root` inside it is the worktree. `cc --no-worktree` → none. Open the project twice → two distinct worktrees. `cc --resume <id>` → **no new worktree**, and the session lands back in its old one — question 1's untested half. |
| 8 | Rewrite `docs/cc-worktree.md`. | — |

Step 4 is the only irreversible-feeling one; steps 1–3 are exercised entirely by
hand and by tests before any hook exists. Step 7 is deliberately last: it is the
only step that changes what happens when the user types plain `cc`, and if
question 1 turns out wrong it is the only step that has to change.

---

## 9. Tests

`cmds test` from the dotfiles root, never bare pytest. `lib/python` is already a
registered component. Each test names the defect it pins.

| Test | Defect pinned |
|---|---|
| `jj_root_inside_worktree_is_the_worktree` | **the whole bug**: `jj` resolving to the parent, so `jj commit` in a worktree commits another session's work |
| `git_toplevel_inside_worktree_is_the_worktree` | the mirror bug a bare `jj workspace add` would ship — and CC's own exit prompt reading the parent's dirt |
| `git_status_clean_after_attach` | forgetting `reset --mixed`: every file shows `D` + `??`, so CC's prompt claims total loss on an untouched tree |
| `attach_failure_still_returns_jj_workspace` | failing creation outright over a degraded-but-correct worktree |
| `stdout_is_exactly_one_line` | a warning on stdout becoming the "last line" and CC cd-ing into a warning |
| `refuses_name_with_slash_and_dotdot` | a path escape, and a worktree `EnterWorktree` can never find again |
| `refuses_dotfiles_root` | isolating the one checkout that cannot be isolated |
| `refuses_nested_worktree` | `w/.claude/worktrees/w2`; asserts `.jj/repo` is a file and `--git-dir` ≠ `--git-common-dir` |
| `create_is_idempotent_after_kill` | the hook timeout killing us mid-build wedges that name forever |
| `create_makes_no_vcs_call_outside_a_repo` | cost and a regression surface on every non-repo `--worktree` |
| `remove_trashes_never_deletes` | **the retiring design's killer**: `git worktree remove` returns 0 and deletes `.env`, `.venv`, `node_modules` |
| `remove_bookmarks_before_forget` | after `forget` the commit leaves the default revset — work becomes unfindable |
| `remove_snapshots_before_bookmarking` | reproduced today: without `jj -R <wt> st` the bookmark is `Target revision is empty` and the work exists only in the trash |
| `remove_refuses_path_outside_managed_dir` | a `worktree_path` naming the repo root, `$HOME`, or a parent of cwd |
| `remove_nonzero_when_trash_fails` | continuing past a failed trash leaves a non-empty dir where `git worktree add` fails forever — and lets CC's `git worktree remove --force` fallback run |
| `remove_is_idempotent` | a half-finished remove wedging that name |
| `remove_of_unknown_path_is_a_noop` | a worktree created before the hook existed, or a plain git one |
| `symlink_entry_never_deletes_parent_content` | `link_one` **deleted real files in the parent** — an entry for a directory followed by one underneath it, and absolute-path entries. Reproduced twice in the retiring design. |
| `worktreeinclude_copied_when_hook_configured` | registering the hook silently removing `.worktreeinclude` from every plain git repo |
| `symlink_directories_setting_honoured` | the same for `worktree.symlinkDirectories` |

Wrapper argv tests go in the **same file**, driving `fish -c` with a PATH shim
that records the argv `claude` was called with. `tests/fish/` is orphaned and
never executes — `cmds test` runs the `lib/python` component only, which is why
the old `test_cc_worktree_wrapper.py` proved nothing.

| Test | Defect pinned |
|---|---|
| `no_marker_appends_nothing_and_forks_nothing` | a cost and a regression surface on every launch in every un-opted-in repo |
| `opted_in_appends_worktree_with_unique_name` | the feature not happening at all — the whole point of the amendment |
| `two_launches_get_different_names` | question 5: a stable name puts two concurrent sessions in **one** worktree via `ucs()`'s "Resuming existing worktree" branch |
| `no_worktree_flag_is_stripped_and_suppresses` | `claude` dying on an unknown `--no-worktree`, or the opt-out not opting out |
| `skip_extras_appends_nothing` | a worktree leaked per headless `-p` run from `ai.fish` / `ccpu` / `sanctuary` |
| `resume_appends_nothing` (all five spellings) | a second worktree created for a session that already has one |
| `user_supplied_worktree_is_not_doubled` | `-w`, `--worktree`, `--worktree=x`, `--worktree x` |
| `appended_flag_is_two_argv_elements` | the fish list-vs-string trap: `"--worktree name"` as one element reaches `claude` as an unknown flag |
| `should_isolate_refuses_inside_a_worktree` | a worktree inside a worktree, reached by `cd`-ing into one and typing `cc` |

Two lessons from `test_llm_output.py` that apply here: a test that locates a file
**via the value under test** is circular, and whole features can be invisible
(`--contract` shipped with no test at all). `hook-create`'s stdout discipline and
the `.worktreeinclude` path are the two most likely to ship untested.

---

## 10. Not doing

The amendment deletes essentially all of `cc-worktree`'s machinery. What survives
is: the marker (`on`/`off`/`status`/`should-isolate`), the link/copy primitives,
`trash`, the backend detector, and the two hook subcommands. Everything below is
**gone**, not deferred.

- **Slots.** `w-NN`, `.owner`, `pid` + `ps -o lstart=` liveness, `os.link`
  claiming, `MAX_SLOTS`, `claim`/`drop_owner`, the whole race design. CC names
  worktrees; the wrapper names them when it appends the flag.
- **The reaper.** `reap`, `reap --all`, the `$XDG_STATE_HOME/cc-worktree/repos`
  registry, the piggybacked reap on launch, the `flock` around it (the hook keeps
  a smaller one, around creation only).
- **Holds.** `.hold`, `write_hold`/`drop_hold`/`hold_reason`, `slot_dirty` as a
  reap gate, "uncommitted (crashed)". CC's exit prompt asks the question.
- **Merge-back.** `finish`, `merge_and_release`, `land`, `land_git`, `release
  --land`/`--discard`, the `would be overwritten` branch, the parent-branch-moved
  check, the stash/untracked-clash handling.
- **Anything that moves the shell.** The wrapper does not `cd`, so there is no
  exit path, no `_cc_orig_pwd`, and no "cd back before finishing".
- **Slot-aware resume, and all `ccs` involvement.** `__cc_resume_id`,
  `__cc_resume_requested`, `slot-for-session`, `current`, the `slot` field in ccs
  entries, and the five `ccs.fish` re-keys. The launch directory no longer moves,
  so every `ccs` key is what it always was, and CC restores the worktree from the
  resumed conversation's own `worktreeSession`.
- **`_cc_worktree_key` / `_cc_worktree_slot`.** Nothing maps a worktree path back
  to a parent any more.
- **`chpwd` hold surfacing.** No holds exist.
- **Covering entry points other than the `cc` abbr.** Split now: the *hook* is
  global, so bare `claude`, the IDE extensions and the desktop app all get
  correct jj worktrees. The *automatic* `--worktree` is only on the `cc` path,
  so a bare `claude` in an opted-in repo runs un-isolated. Document it; it is a
  smaller gap than before and in the safe direction.
- **Locking the worktree.** CC skips `qDu()` for hook-based worktrees, so two
  sessions could in principle be told to enter the same one. Our `flock` covers
  creation; concurrent *entry* is CC's business.
- **Policy/managed settings** when merging `worktree.*`.
- **Garbage-collecting worktrees left by crashed sessions.** `WorktreeRemove`
  never fires on SIGKILL / `Cmd+Q` / power loss, and CC does not reap them
  either. `cc-worktree status` lists them; removing one is
  `cc-worktree hook-remove` with that path. A reaper is what the retiring design
  spent most of its complexity on, and it is not worth rebuilding for a case the
  user can see and resolve in one command.

### What happens to the committed code

`lib/python/cc_worktree.py`, `bin/cc-worktree`, `docs/cc-worktree.md` and
`tests/lib/python/test_cc_worktree.py` are **rewritten in place**, keeping the
name: the CLI is still `cc-worktree`, it is still the thing that owns
`<repo>/.claude/worktrees/`, and the git history stays attached to the guards
worth keeping. The four fish functions, `tests/fish/test_cc_worktree_wrapper.py`
and the `.gitignore` negations are **trashed** (`trash`, per CLAUDE.md — not
`rm`, and never chained). The wrapper, `ccs.fish` and `chpwd.fish` are reverted
by hand; their comments explain guards that no longer have anything to guard, so
delete the comments with the code.

Commit the retirement as its own change, after step 4 is verified, so a bisect
lands on a repo where exactly one isolation mechanism exists.

---

## 11. Accepted risks

| Risk | Status |
|---|---|
| The `.git` move + `worktree repair` is not a documented composition of jj and git | both halves are documented individually (`gitrepository-layout`, `git worktree repair`); the attach is best-effort and its failure degrades to a working jj workspace; `git_toplevel_inside_worktree_is_the_worktree` fails loudly if a future jj or git breaks it |
| jj imports `worktree-<name>` as a bookmark in a colocated repo | cosmetic; `git branch -d` at remove, and jj's next import drops the bookmark |
| Work snapshotted after the last `jj -R <wt> st` is not in the bookmark | unavoidable — the parent cannot snapshot another workspace. The remove hook snapshots *first*, and the trash covers the rest |
| A `svc` dev server or editor holds files in the worktree at remove | trash-not-delete makes it recoverable |
| An agent that ignores CLAUDE.md and runs `git` in a **non-colocated** jj worktree | there is no `.git` anywhere in such a repo, so git errors rather than addressing the parent |
| A repo where `.claude/` is not ignored shows `?? .claude/` in the parent's `git status` | pre-existing native behaviour, unchanged by this plan; the parent's **jj** is unaffected (verified) |
| Hook timeout on a very large `jj workspace add` | 300 s, and `create` is idempotent on re-run |
| Worktrees accumulate under `.claude/worktrees/` when sessions are killed rather than exited | `cc-worktree status` lists them; each is one `hook-remove` away. No reaper — see §10 |
| Question 1 (resume) is verified from the binary, not end to end | it is step 7, the last step, and the only one that would have to change |
| `cc-worktree should-isolate` adds ~50 ms to every interactive `cc` | one process, only on the `cc` path, and it buys a single tested implementation of marker lookup + nesting + the `~/dotfiles` refusal |
