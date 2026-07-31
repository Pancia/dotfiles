# Per-session worktree isolation (`cc-worktree`)

## Setup: one command, once per checkout

```bash
cd ~/projects/whatever
cc-worktree on          # probes the repo, writes the marker, prints what it found
```

That is the whole setup. It is permanent — a file in the repo's VCS directory —
so it survives reboots, new terminals and new sessions, and it does not travel to
other machines. From then on `cc` in that repo puts each session in its own
worktree. `cc-worktree off` undoes it.

**Not in `~/dotfiles`** — it refuses there by name, because that checkout cannot
be isolated. Use [`ccjj` / `commit-mine`](cc-jj-sessions.md) instead.

## The problem

Two Claude Code sessions in one checkout tread on each other: they edit the same
files, run the same build, and each `jj commit` sweeps up whatever the other has
half-written.

[`ccjj` / `commit-mine`](cc-jj-sessions.md) solves that for `~/dotfiles`, which
**cannot** be isolated — about 46% of its tracked files load by absolute path (every
`rcs/MANIFEST` hardlink, `~/.config/fish/functions`, `PATH`, `PYTHONPATH`,
Hammerspoon's `package.path`), so a second checkout can author changes it cannot
run. Every *other* repo can be isolated, and there the ordinary answer works:
give each session its own git worktree / jj workspace.

`cc-worktree on` opts a checkout in. After that the `cc` wrapper creates a
worktree and `cd`s into it before launching claude, and merges or holds the work
when the session ends.

**The two compose without knowing about each other.** Inside a workspace `jj root`
returns the *workspace*, so `ccjj` sees a repo where this session is the only one:
`should-scope` declines, the nudge stays silent, and an ordinary whole-copy commit
happens — which is the better outcome there, because it also captures Bash-made
changes `commit-mine` cannot see. Nothing needs configuring for that, and
`ccjj` deliberately has no worktree-awareness: it already declines for the right
reason, and teaching a correctness tool to detect its environment only adds a way
for it to be wrong.

## Usage

```bash
cc-worktree on                     # opt this checkout in (writes the marker)
cc-worktree status                 # marker, link list, slot state
cc-worktree off                    # opt out

cc-worktree land w-03              # bring a held slot's work into the parent
cc-worktree release w-03 --land    # the same, then free the slot
cc-worktree release w-03 --discard # trash it — the ONLY path that loses work
cc-worktree reap [--all]           # release finished slots
```

`release` with neither `--land` nor `--discard` refuses and prints both: the old
`--force` name was ambiguous between "clear the hold" and "throw the work away".

Held slots are surfaced by `chpwd` when you `cd` into the repo, in the same
orange as pending CLAUDE.md updates.

## The marker and the link list

The opt-in marker *is* the config. It lives at `<git-common-dir>/cc-worktree`
(git) or `<repo>/.jj/cc-worktree` (jj) — **never** `<repo>/.git/cc-worktree`,
because `.git` is a *file* in a linked worktree and in a submodule.

```
# <repo>/.git/cc-worktree
.cc-config
.claude/settings.json
.claude/settings.local.json
.envrc
node_modules
.venv
copy:.tool-versions
max-slots: 4
```

**`cc-worktree on` writes that list by probing the repo**, rather than applying a
fixed default. It proposes every candidate that both **exists** and is **not
tracked**, and says what it found:

```
$ cc-worktree on
cc-worktree: detected 3 path(s) to share with each worktree:
    .claude/settings.local.json
    .env
    node_modules
  (tracked, so already in every checkout: .claude/settings.json)
```

Both halves of that test matter. A tracked path arrives in the checkout by
itself, and linking it would route every worktree edit around the VCS. An absent
one is just noise.

A static default was wrong in the direction that costs you: it shipped `.envrc`,
which no project here has, and omitted `node_modules` and `.env` — so a real Node
or Python session started with no dependencies and no secrets, which is precisely
the "unusable, switched off within a week" failure the link list exists to
prevent. What a worktree must borrow is a property of the repo, so ask the repo.

Candidates are in `PROBE_ENTRIES`: Claude Code's own per-project state
(`.cc-config`, `.claude/settings*.json`, `.claude/skills|agents|commands`,
`.mcp.json`), environment and toolchain (`.env*`, `.envrc`, `.direnv`,
`.tool-versions`, `.nvmrc`, `.python-version`, `.ruby-version`), and installed
dependencies (`node_modules`, `.venv`, `vendor/bundle`, `target`, `.next`,
`.gradle`, `.terraform`, `_build`, `deps`). Edit the marker afterwards for
anything it missed — it is a plain file and it is only written on first opt-in.

Every entry is **symlinked** into each worktree, absolute and parent-pointing.
Edits through the link land in the parent — which is what you want for `.envrc`,
`node_modules`, `.venv`, and for permission grants accruing to
`settings.local.json`. It also means removing a worktree destroys none of them.
`copy:` copies instead, for the rare path that must diverge. Missing entries are
skipped silently; that is the normal case. With no entries at all, the first four
lines above are the default.

The list is **mandatory, not a nicety**: `gitignore_global` line 2 is `.*`, so
`.claude/`, `.cc-config` and `.envrc` are absent from a fresh worktree — and
`cc-config sync` would then no-op and the session would run unconfigured, with
nothing said.

`cc-worktree on` **refuses** when the repo root is `~/dotfiles`, when it is
already a linked worktree/workspace or inside a slot, and — for jj only — when
any link-list entry is not ignored. jj auto-tracks, so a symlinked
`node_modules` in a workspace is snapshotted **as a symlink pointing into the
parent** and committed into history. jj has no `check-ignore`, so the check is
done by building a probe workspace, linking the list into it and reading
`jj st`. It **warns** about non-ignored entries under git, about submodules, and
about a dirty working copy.

## Slots

`MAX_SLOTS` is 10, overridable with `max-slots: N`. A slot is claimed by
hard-linking a fully-written `.owner` record into place: `os.link` is atomic and
fails `EEXIST`, so two shells racing cannot land in the same worktree, and there
is no window in which `.owner` exists but is empty.

Slots are **reused**, which is what bounds `~/.claude.json` growth (it already
has ~593 project entries) and disk. The name is derived from the slot, not the
pid, because `$fish_pid` is stable per terminal and a pid-derived name collides
on the next launch from the same window.

`.owner` records pid + `ps -o lstart=` — the same identity check `ccs` and `ccjj`
use, because a recycled pid otherwise makes a dead slot look live forever.

**Known, accepted:** relaunching from a shell whose previous session crashed sees
that slot's owner as *alive* (same pid + lstart) and leaves it. That is the
conservative direction — the crashed session's work stays on disk — and it costs
one slot until the shell exits.

## Ending a session

A **hold** is the normal ending, not an exception: most sessions stop with
uncommitted edits (Ctrl-C mid-task, "commit later"). A held slot keeps its tree,
its branch and its `.owner`, and **nothing in this system ever reaps it**.

| At exit | What happens |
|---|---|
| worktree dirty | HOLD `uncommitted`; `cc-worktree land w-NN` gets it back |
| git, merges clean | merge into the parent, then release |
| git, conflict | `git merge --abort`, HOLD, print `git merge w-NN` to retry |
| git, "local changes would be overwritten" | HOLD, print `git stash && git merge w-NN && git stash pop`. **No** `--abort` — there is no merge in progress and `--abort` exits 128 |
| git, parent moved branch | HOLD, naming both branches. Checked *before* the merge |
| jj, clean | release. Bookmarks are repo-global, so the session's own `jj commit` + `jj bookmark set master -r @-` already advanced master |

Recovery is ordinary: `git merge w-NN` from the repo root. Different files merge
clean, same file/different lines merges clean, and only same-line edits conflict.
The agent *inside* the worktree cannot run it (`fatal: 'master' is already
checked out`), which is why the wrapper `cd`s back out first.

## Reaping

The reaper runs at every wrapper launch (piggybacked, like `ccjj prune`) and via
`cc-worktree reap [--all]`, under an `flock` — two launches racing means one's
`git worktree prune` can drop a registration the other's `git worktree add` is
mid-way through creating.

It enumerates the **union** of `w-*.owner` files, `w-*` directories, and backend
registrations, so no state that exists in only one of the three is invisible.
`git worktree list --porcelain` is captured **once at the top** and carried
through: the prune destroys the registration the branch is read from, and an
orphaned branch makes every later `create` fall back to `w-NN-<stamp>` forever.

A dead owner whose tree is **dirty** gets `.hold "uncommitted (crashed)"` rather
than a release: SIGKILL, `Cmd+Q` and `tmux kill-session` all skip the exit path,
so the crash case reaches the reaper, and trashing there loses the only copy.

Release order, where each step leaves a state a re-run finishes:

1. jj only: `jj bookmark set w-NN-<stamp> -r 'w-NN@'`. **Before** forgetting —
   afterwards the working-copy commit is not in the default revset. Run from the
   parent; the reaper never enters the workspace.
2. `trash <wt>`. **Never** `git worktree remove`: without `--force` it returns 0
   and *deletes ignored files*. A nonzero `trash` **aborts** the release with
   `.owner` intact — continuing would leave a non-empty directory at the slot
   path, and `git worktree add` then hard-fails there forever.
3. unregister (`git worktree prune` / `jj workspace forget`), both idempotent.
4. git only: `git branch -d`. **Not `-D`** — `-d` refuses an unmerged branch, and
   that refusal is the recovery handle for the work just preserved.
5. `rm <wt>/w-NN.owner`, **last**: while it exists the slot is claimed, so an
   interrupt anywhere above is re-processed rather than orphaned.
6. trash the `cc-jj-journal/<worktree-path>/` namespace.

Anything skipped is **named on stdout**, never silently — except inside
`create`, where the same notices go to stderr because stdout is the directory the
wrapper `cd`s into.

## Resume

`claude --resume <id>` is scoped to the project directory: Claude Code keys
transcripts by mangled cwd (`-Users-anthony-proj` vs
`-Users-anthony-proj--claude-worktrees-w-01`). A session that ran in `w-01` and
is resumed from the parent gets *"No conversation found with session ID"*.

So the slot determines the path, and reusing the slot restores resumability. The
ccs entry records `slot` alongside `cwd`; the wrapper scans argv for
`--resume <id>` / `-r <id>` / `--resume=<id>`, asks `cc-worktree
slot-for-session`, and passes `--slot w-NN --reuse`. The transcript lives in
`~/.claude/projects/`, not in the worktree, so the tree need not have survived —
only the path has to be the same. A surviving (held) tree is adopted as-is, which
is what "resume the session I Ctrl-C'd" actually wants.

A bare `-c` / `--continue` carries no session id, so its slot cannot be looked up
and it runs un-isolated. Same for an entry that predates this feature: its
transcript is keyed to the parent, so the parent is where it resumes.

## `ccs` re-keying

`_cc_worktree_key` maps `<repo>/.claude/worktrees/w-NN[/sub]` back to
`<repo>[/sub]`. It uses `$PWD` (logical), **not** `pwd -P`: every `ccs` site it
replaces uses logical pwd, and `/tmp` → `/private/tmp` and `~/Cloud` (a
ProtonDrive symlink) diverge, which would silently orphan every existing entry.
It is pure fish with no subprocess, because it runs on every `cd` through
`chpwd` → `_ccs_open_scan`.

Re-keyed sites: `_ccs_file`, `_ccs_backup_session`, `_ccs_open_register`,
`_ccs_open_scan`, `_ccs_old`. `_ccs_migrate` is left alone (it reads legacy
in-repo paths), as are `_ccs_prune` and `_ccs_restore_transcript`, which read
`.cwd` from the entry file — already written with the key, and therefore already
consistent.

Outside a worktree the key *is* `pwd`, so the whole change is a no-op everywhere
else.

## Not covered

- **Entry points other than the `cc` abbr.** Bare `claude`, the IDE extensions,
  the desktop app and any direct `claude -p` all bypass the wrapper, so a repo
  can hold one isolated and one non-isolated session at once.
- **`~/dotfiles`.** `on` refuses; `ccjj` owns that case.
- **`ccjj` worktree-awareness.** It already self-disables correctly in a
  workspace (own `.jj` → own repo key → no peers → whole-copy commit, which is
  *better* there). Only its journal namespace needs cleaning up, which the reaper
  does.
- **Pre-trusting new cwds in `~/.claude.json`.** One trust dialog per slot per
  repo on first use, bounded at `MAX_SLOTS` by reuse.
- **Submodules beyond `git submodule update --init --recursive`.** jj has no
  equivalent; `on` warns.

## Accepted risks

| Risk | Why it is acceptable |
|---|---|
| A `svc` dev server or editor holds files in the worktree | trash-not-delete makes it recoverable |
| A jj session's post-last-snapshot edits are not in the bookmark | unavoidable — the parent cannot snapshot another workspace. The reaper snapshots first and then *holds*, so nothing is trashed unseen |
| A crashed shell's slot is not reaped until that shell exits | conservative: the work stays on disk |
| A repo you stop visiting keeps its worktrees | `reap --all` plus the `chpwd` hold notice |
| Two sessions share `node_modules` / `.venv` through the links | deliberate — a repo needing divergence uses `copy:` |
| `trash` moves to `~/.Trash`, so a repo on another volume makes release a cross-device copy | on the critical path of every launch; noticeable only on very large trees |

## Files

| Path | Responsibility |
|---|---|
| `lib/python/cc_worktree.py` | all the logic: marker, link list, slots, create/reap/release/land/finish |
| `bin/cc-worktree` | shell entry point |
| `fish/functions/_cc_worktree_key.fish` | worktree path → parent repo path |
| `fish/functions/_cc_worktree_slot.fish` | worktree path → slot name |
| `fish/functions/__cc_resume_id.fish` | argv scan for `--resume`/`-r` |
| `fish/functions/my-claude-code-wrapper.fish` | creates the worktree, `cd`s in, runs the exit path |
| `fish/functions/ccs.fish` | five re-keyed sites; records `slot` in the entry |
| `fish/functions/chpwd.fish` | `showHeldWorktrees` |
| `tests/lib/python/test_cc_worktree.py` | logic tests |
| `tests/fish/test_cc_worktree_wrapper.py` | key/slot functions and the wrapper end to end |

Exit codes: `0` ok · `1` refused or failed · `2` not opted in. Exit 2 keeps the
common case to one process and zero output — `create` makes **no git or jj call
at all** in a repo that has not opted in, which is a test.

**Adding another `_`-prefixed fish function here needs a `.gitignore` negation.**
`.gitignore:14` is `fish/functions/_*` (it keeps plugin internals out), so all
three functions above are ignored by default — they were untracked and would
never have shipped. The exceptions sit next to `_claude_release_notes.fish`,
which is there for the same reason. Autoloading is what forces them to be
separate files: fish autoloads by filename, and `_cc_worktree_key` runs on every
`cd` and inside `fish -c` subshells, so it cannot be folded into `ccs.fish` the
way the `_ccs_*` helpers are.
