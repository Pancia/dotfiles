# Per-session worktree isolation (`cc-worktree`)

Two Claude Code sessions in one checkout tread on each other: they edit the same
files, run the same build, and each `jj commit` sweeps up whatever the other has
half-written.

[`ccjj` / `commit-mine`](cc-jj-sessions.md) solves that for `~/dotfiles`, which
**cannot** be isolated — about 46% of its tracked files load by absolute path
(every `rcs/MANIFEST` hardlink, `~/.config/fish/functions`, `PATH`, `PYTHONPATH`,
Hammerspoon's `package.path`), so a second checkout can author changes it cannot
run. **Every other repo can just be copied**, and Claude Code has created git
worktrees natively since v2.1.49 — so all this tool does is record that a
checkout wants them.

## Setup: one command, once per checkout

```bash
cd ~/projects/whatever
cc-worktree on          # probes the repo, writes the marker, prints what it found
cc-worktree status
cc-worktree off         # undo

cc --no-worktree        # opt out for a single run
```

It is permanent — a file in the repo's VCS directory — so it survives reboots,
new terminals and new sessions, and it does not travel to other machines. From
then on `my-claude-code-wrapper` appends `--worktree <name>` and **Claude Code
does the rest**: it creates the worktree under `.claude/worktrees/<name>`, cd's
into it, returns you there on `--resume`, and prompts to keep or remove it on
exit.

**Not in `~/dotfiles`** — it refuses there by name. Use
[`ccjj` / `commit-mine`](cc-jj-sessions.md) instead.

---

## The one thing to know: inside a worktree, use `git`

`claude --worktree` in a colocated jj repo **succeeds**, and that is the problem.
It creates a *git* worktree, which has no `.jj` of its own — so `jj` run inside
it walks up the tree and resolves to the **parent repo**.

An agent that runs `jj commit` in a worktree therefore commits **the parent's
working copy** — very likely a peer session's in-flight work — while its own
changes stay uncommitted. Nothing about this is obvious: the worktree's files are
invisible to the parent's jj too, because `.claude/` is ignored by
`git/gitignore_global`.

**The hazard is active, not passive.** A repo's `CLAUDE.md` is a tracked file, so
git checks it out into the worktree and Claude Code loads it there — measured,
not assumed. In this repo and in AKR that file says *"use jj for all VCS
operations"*. So the agent is being **instructed** to do the harmful thing, and a
warning has to *override* a standing instruction rather than fill a silence.

The remedy is not a consolation prize. Commit with git inside the worktree and
the parent picks the branch up as a **jj bookmark of the same name,
automatically** — jj auto-imports git refs in a colocated repo. Verified: the
commit appears in the parent's plain `jj log`, and the parent's working copy is
untouched.

### `bin/cc-worktree-nudge`

A `UserPromptSubmit` hook that injects exactly that, in the one situation where
it applies. It fires when **`.git` is a file** (a linked worktree) **and** the
repo it points back at has a `.jj/`.

- **`UserPromptSubmit`, not `SessionStart`.** The fact barely changes
  mid-session, but a rule stated once gets forgotten over a long conversation and
  can be dropped by compaction; a safety rule should re-assert. It is also the
  only event that fires before an agent whose *first* action is a Bash
  `jj commit` — the case that loses data.
- **It contains the answer, not a pointer.** An agent may not follow a link.
- **The silent path spawns no subprocess** — no `cat`, `grep`, `sed` or `git`,
  only bash builtins and at most four stat calls. It runs on every prompt in
  every project. (Pinned by a test that runs it with an empty environment: if it
  shelled out to anything, it could not find it.)
- It resolves the parent from the `gitdir:` pointer rather than assuming the
  worktree sits inside it, so a hand-made `git worktree add /tmp/wt` is covered.
- On a detached HEAD it says so instead of promising a branch the parent will
  never see.

---

## What `cc-worktree on` does

**Writes the marker.** `<git-common-dir>/cc-worktree`, or `.jj/cc-worktree`.
Both are outside the working tree on purpose: opting in is a property of *this
checkout*, not of the project, so it never shows up as an untracked file or
travels to anyone else in a commit.

Never `<root>/.git` — in a linked worktree and in a submodule that is a **file**,
so joining a filename onto it gives a path that can never be opened, and the
marker would silently not be found.

**Writes a starter `.worktreeinclude`.** That is Claude Code's own mechanism for
carrying untracked local state into a new worktree, and without it a session
starts with no permissions granted and no environment. `on` probes the repo and
proposes only paths that **exist** and are **not tracked** — a tracked path
arrives in the worktree by itself.

The list is deliberately limited to small config (`.env`, `.cc-config`,
`.claude/settings*.json`, `.mcp.json`, version pins). **`.worktreeinclude` copies
rather than links** (measured), so `node_modules` or `.venv` there would be slow
and waste disk on every session — and a copied `settings.local.json` means
permission grants stop accruing to the parent. Those are left for you to add
knowingly. An existing `.worktreeinclude` is never overwritten.

**Refuses where it must.** `~/dotfiles` by name; and a linked git worktree or a
jj workspace, because from inside one `--git-common-dir` finds the *parent's*
marker and would happily nest a worktree inside a worktree.

## When the wrapper appends `--worktree`

All of these must hold:

| condition | why |
|---|---|
| `cc-worktree should-isolate` exits 0 | the per-checkout marker |
| not `-p` / `--print` | `ai.fish`, `ai_health`, `ai_inbox`, `ccpu` and `sanctuary/main-claude` all route through this wrapper headless, and would each leak a worktree per run |
| not a resume (`-r`/`--resume`/`-c`/`--continue`) | Claude Code already returns a resumed session to the worktree it ran in; adding the flag would strand it in a fresh empty one |
| no `-w` / `--worktree` / `--worktree=x` / `-wname` already present | the user's own choice wins |
| no `--no-worktree` | the explicit opt-out |

`--no-worktree` is consumed by the wrapper and **never forwarded** — claude does
not know the flag. It is matched *before* the `--process-label` value branch, or
`cc --process-label --no-worktree` takes it as the label text and the opt-out
silently does nothing.

The name is generated (`cc-HHMMSS-$fish_pid`). A stable default would put two
concurrent sessions in one worktree, which is the opposite of the point.

`should-isolate` makes **no git or jj call at all** — the marker is resolved by
reading `.git` and `commondir` by hand, exactly as git does — so a launch in a
non-opted-in repo pays nothing for a feature it does not use.

---

## What was deleted, and why

This tool was 1413 lines. It had slots (`w-01`…`w-10`), `.owner` and `.hold`
files, a flock, a reaper, `create`/`finish`/`land`/`release`/`current`, a
symlink-based link list, and slot-aware resume. All of it existed for one reason:
**the wrapper created the worktree itself and cd'd into it before launching
claude**, which hid the worktree from Claude Code — so Claude Code could not
name, resume, list or clean up its own sessions, and every one of those jobs had
to be reimplemented here.

Handing the job back deleted all of it, along with the bugs it carried —
`link_one` was caught deleting files in the parent repo, resolving a destination
*through* a symlink it had just created.

Also gone: `_cc_worktree_slot.fish`, `__cc_resume_id.fish`, `showHeldWorktrees`
in `chpwd.fish`, and the `slot` field in ccs entries.

`_cc_worktree_key` survives, and its regex was widened from `w-\d+` to any single
path segment. Claude Code's generated names (`warm-discovering-metcalfe`) do not
match the old pattern, which made it a silent no-op for every native worktree —
filing sessions under the worktree path instead of the repo, exactly what it
exists to prevent. Filing under the parent is right because **`claude --resume
<id>` run from the parent reaches a worktree session on its own** (verified), so
ccs never needs to know which worktree it was.

## Things measured, not assumed

Each of these was checked because getting it wrong fails silently:

- **`SessionStart` carries the real cwd.** `--worktree` makes claude cd *after*
  the wrapper has launched it, so the wrapper's `pwd` is the parent while the
  transcript is keyed to the worktree. `bin/ccsave-hook` records the real cwd
  into the ccs entry and the wrapper reads it back afterwards; computing it from
  `pwd` looked in a directory the session never wrote and skipped the
  post-session review in silence.
- **`.worktreeinclude` copies, and works.** A worktree created before the file
  existed lacked the entries; one created after had them, as regular files.
- **A tracked `CLAUDE.md` loads inside the worktree.** An untracked one does not
  — it is simply not in the checkout.
- **fish 4 dropped `?` as a glob wildcard.** `string match -q -- 'x?*' xmine`
  returns 1. The obvious pattern for "`-w` followed by something", `-w?*`,
  matches nothing at all, so `-wname` silently got a second `--worktree`
  appended.
- **This machine's global gitignore begins `.*`**, so every dotfile is ignored
  and `git add` silently refuses it. Test repos that need to track one must set
  `core.excludesFile` themselves.

## An alternative that was measured and not taken

`.claude/rules/*.md` with a **`paths:`** frontmatter field (not `globs:` — that
name is Cursor's) loads a rule only when Claude Code touches a matching file. A
rule with `paths: [".claude/worktrees/**"]` in the *parent* repo does fire inside
a worktree session and stays silent outside it — reproduced 3/3 with a control,
and it needs no commit, since `.claude/` is gitignored and the file is read from
the parent.

It was still not used for the warning, for one decisive reason: **it only fires
when the agent touches a file**, and the case that loses data is a session whose
first action is a Bash `jj commit`. Secondary: bare `**` does not match (dotfile
segments), and frontmatter-less rules did not load in worktree sessions at all —
edges I did not want a safety guarantee resting on. The hook's detection is plain
filesystem logic with no such surprises.

A `WorktreeCreate` hook that made a real **jj workspace** instead of a git
worktree is the better feature and remains unbuilt: it is a global hook whose
failure mode is deletion, it rests on undocumented internals the published docs
get wrong on at least two points, and it would take over `--worktree` in the 45
git repos as well as the 6 jj ones. The plan survives at `.cc/PLAN-jj-worktree-hook.md`.

## Tests

- `tests/lib/python/test_cc_worktree.py` — refusals, marker location, the
  `should-isolate` gate (including "makes no VCS call" via a PATH spy), and
  `.worktreeinclude` generation.
- `tests/fish/test_cc_worktree_wrapper.py` — argv construction: the flag is
  appended when opted in, suppressed for `-p`/resume/explicit-`-w`, and
  `--no-worktree` is honoured and never forwarded.
- `tests/hooks/test_cc_worktree_nudge.py` — one positive case and eight
  negatives, plus JSON validity. That check earns its place: backticks were once
  emitted as `\``, which is not a legal JSON escape, and Claude Code discards a
  malformed payload **silently** — the hook still exited 0 and still printed
  ~800 bytes, so every eyeball check passed while the warning never arrived.

Run with `cmds test python`, `cmds test fish`, `cmds test hooks`.
