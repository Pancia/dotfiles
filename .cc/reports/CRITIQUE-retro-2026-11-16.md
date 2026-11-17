# Critique of the 2026-11-16 retro suggestions

Five suggestions from the retro of the session that built `roleplay-bookends`
features, `roleplay-roll`/`roleplay-say` changes and `bin/scratch`. Each one was
attacked first. Behaviour checks ran in throwaway `scratch new` copies, now
discarded. No file in the repo was changed except this report.

| # | Suggestion | Verdict |
|---|---|---|
| 1 | Link `ai/mods/README.md` from CLAUDE.md | **changed**: one table row, no inline sentence; optional nested `ai/mods/CLAUDE.md` |
| 2 | README bullet: open panes with `backgroundColor: 'transparent'` | **changed**: the cause is the custom theme; fix it there (an experiment the user must check by eye) |
| 3 | ccjj: ignore an ended session's offered window | **changed**: the diagnosis is half wrong, and the proposed rule is unsafe. Sweep spent offers at commit time instead (tested) |
| 4 | One shared `tests/world.tsx` | **confirmed, with a changed shape**: a factory with options, not one fixed world |
| 5 | Global rule: syntax-check Python with `ast.parse` | **rejected**: the proposed command is weaker, and the harm is already nil |

---

## 1. Link the mods README from the project CLAUDE.md

**Diagnosis: true.** `grep` finds `ai/mods` in the project CLAUDE.md only in the
dated reminder (line 16) and inside two long Quick Reference cells (`plainify`,
line 322; `roleplay-roll`, line 327). `CLAUDE_CODE_PLUGIN_DIRS` appears once, in
the `plainify` cell. Nothing points at `ai/mods/README.md`.

**The README's command works.** `npx -y -p typescript@5.6.3 tsc -p <mod>` ran
on a copy of `roleplay-bookends` in 1.4 s with no errors. It also checks
`tests/`: the engine's `.claude-plugin/types/tsconfig.json` includes
`../../hooks`, `../../types` and `../../tests`, and a planted type error in a
test helper was reported. So a session that had read the README would not have
borrowed `~/projects/claudecodeui/node_modules/typescript`.

**Why the reviewer subagent could not type-check is not proved.** A pointer
only helps if it lacked the command. If it lacked network or Bash permission,
no CLAUDE.md line fixes that.

**Placement.** The proposed inline sentence would go into the `plainify` table
cell, which is already about 90 words on another subject. A directive there is
easy to miss and adds cost twice. One row in "Detailed Documentation" can carry
the directive itself.

**Cost.** CLAUDE.md is input on every request in this repo (about 38.7 KB now).
The row below is 229 characters, about 55 input tokens per request (estimate:
about 4 characters per token). The inline sentence would add about 17 more.
Both are input tokens, cached after the first request.

**Zero-cost option.** A nested `ai/mods/CLAUDE.md` costs nothing until a
session Reads, Edits or Writes a file under `ai/mods/`. Editing a mod needs a
Read first, so it would load at the right moment. Limits: it does not load for
a Bash `cat`, and I did not confirm that subagents load nested CLAUDE.md files.
A file in `ai/mods/` sits outside every mod folder, so saving it reloads no mod
(the README says the same about itself).

**Revised fix.** Add this row to the "Detailed Documentation" table and skip
the inline sentence:

```
| [ai/mods/README.md](ai/mods/README.md) | Claude Code mods. Read it before editing or checking a mod: hot reload in every session, the pinned `tsc` command, `claude plugin test`, and the copy-to-scratch rule for a risky change |
```

Optional, at zero per-request cost: `ai/mods/CLAUDE.md` with one line, "Read
README.md in this folder before editing or checking any mod."

The `plugin-authoring` skill is built in, so it cannot carry the pointer.

---

## 2. The dark pane backdrop

**Diagnosis: true, but the cause is the theme, not the mods.** The engine
(2.1.326) paints a pane body with the theme key `composerSidebarBackground`
unless the pane asks for `"transparent"`:

```js
function YE(){return zm(Ype)==="transparent"?void 0:"composerSidebarBackground"}
```

In the `dark` base theme that key is `rgb(38, 38, 38)`. The user's theme
`custom:dark-light-term` (`rcs/claude-theme-dark-light-term.json`, hardlinked to
`~/.claude/themes/dark-light-term.json`) is `base: "dark"` on a light iTerm
profile that draws text black. It already overrides one key,
`userMessageBackgroundHover`, for exactly this kind of clash (commit
`xuyvxxmw`, "the light iTerm profile draws its text black"). It does not
override `composerSidebarBackground`, so every pane gets a near-black backdrop
under black text.

**Why a README bullet is the weaker fix.** It fixes one pane at a time, only
in mods that read the README. Panes from other plugins, and the composer
sidebar, which uses the same key, stay unreadable. It also teaches a rule that
does not apply on a normal dark terminal.

**Revised fix (an experiment).** Add one override to the theme file:

```json
{
  "name": "Dark (light terminal)",
  "base": "dark",
  "overrides": {
    "userMessageBackgroundHover": "rgb(225, 225, 225)",
    "composerSidebarBackground": "rgb(245, 245, 245)"
  }
}
```

`rgb(245, 245, 245)` is the value the `light` base theme uses.

- **Expected result:** a pane opened without `backgroundColor` is readable,
  and so is the composer sidebar.
- **If it is still dark:** the `overrides` block does not accept this key
  (unchecked, though it sits in the same palette object as the key that
  already works), or the pane reads another key.

The user must check this by eye. Edit the `rcs/` source, not the live
hardlink.

Keep `backgroundColor: 'transparent'` in `plainify` and `roleplay-bookends`. It
is harmless, and it helps anyone who uses these mods on another theme. Change
the comments to name the cause ("the dark theme's `composerSidebarBackground`
under a light terminal"). Then the README needs no bullet.

---

## 3. `ccjj claim` refuses on an ended session's offer

### What is really there

The ended session is `ab5d1454` (the session that committed the theme at
10:55:58 MST). Its journal now holds only one `.offer` file. It names six paths:
`REVIEW-roleplay-modes.md`, `register.tsx`, `modes.test.tsx`,
`rcs/claude-settings.json`, `claude-roleplay.md` and `test_roleplay_roll.py`.
Its three Bash windows (10:51 to 10:55) spanned the roleplay session's edits,
which were in the working copy then. When `ab5d1454` committed only the theme,
`leave_offers()` correctly offered every path that was still changed and was
covered by its windows.

The working copy at each later commit, from `jj --at-op`:

| After the commit at | Offered paths still changed |
|---|---|
| 10:55:58 (`ab5d1454` commits the theme) | all six |
| 11:00:04 (commit-mine) | only `rcs/claude-settings.json` |
| 15:35, then 15:53 | 4, then only `claude-settings.json` |
| 18:54:04 and 19:00:06 | none |

So five of the six paths were fully committed by 11:00. That means `ab5d1454`
had no bytes left in them. Its offer still made it a "window only" stake on
every later change to those paths, until the prune: 2 days idle with a dead
owner, run by the first commit of a day.

### The diagnosis is half wrong

"Left by an earlier commit" does not mean "its changes were committed". It
means the opposite: that session's commit **left this path uncommitted**. The
label is what misled the retro (see the wording fix below). The real defect is
narrower. Nothing removes a path from an offer when it is committed **by
someone else**. `leave_offers()` prunes only the committing session's own
offers, and an ended session never commits again. The docs say offers last
"until the path stops differing from `@-`", but that holds only for the
owner's own later commits.

### The proposed fix is unsafe

"Do not count an ended session's window as a stake" reopens the bug that
offers exist to close (`docs/cc-jj-sessions.md`, "What `--no-claim` leaves
behind"). A session that commits part of its work and then exits or crashes
leaves Bash-made bytes behind. A peer could then claim them unrefused and commit
them under its own name. `test_a_path_left_by_no_claim_keeps_its_stake` pins
this down, and it accepts `A (ended)`. Liveness is the wrong test. The right
test is whether the path has equalled `@-` at some point since the offer was
written. A path equal to `@-` holds nobody's uncommitted bytes, so dropping it
loses nothing.

That test cannot be made at claim time, because the claimer's new change makes
the path differ again. It must be made when the path is clean, which is right
after a commit. `commit-mine` made the 11:00 commit (its journal was archived
at 10:59:57), so a sweep there would have cleared five of the six paths at
11:00 and the last one at 19:00.

### Revised fix (tested)

In `lib/python/ccjj.py`, add `sweep_offers()` after `leave_offers()`, and call
it once in `cmd_commit()`, after the retire/leave_offers block and before the
`refresh_bases` call:

```diff
@@ after leave_offers() @@
+def sweep_offers(still):
+    """Drop, from EVERY journal's offers, the paths that no longer differ from @-.
+
+    leave_offers() prunes only the committing session's own offers, so an
+    offer from a session that never commits again held its stake until the
+    2-day prune -- even after a peer committed the path in full and then
+    changed it again. A path equal to @- holds no uncommitted bytes of anyone's,
+    so nothing is lost by dropping it. None (jj failed) keeps everything.
+    """
+    if still is None:
+        return
+    base = os.path.join(journal_root(), repo_key(ROOT))
+    if not os.path.isdir(base):
+        return
+    for sid in os.listdir(base):
+        d = os.path.join(base, sid)
+        if sid == "archive" or not os.path.isdir(d):
+            continue
+        for name in os.listdir(d):
+            if not name.endswith(".offer"):
+                continue
+            f = os.path.join(d, name)
+            try:
+                with open(f) as fh:
+                    offer = json.load(fh)
+            except (json.JSONDecodeError, OSError):
+                continue
+            paths = offer.get("paths")
+            if not isinstance(paths, list):
+                continue
+            kept = [x for x in paths if x in still]
+            if kept == paths:
+                continue
+            try:
+                if kept:
+                    offer["paths"] = kept
+                    with open(f + ".tmp", "w") as fh:
+                        json.dump(offer, fh)
+                    os.replace(f + ".tmp", f)
+                else:
+                    spent = os.path.join(d, "spent")
+                    os.makedirs(spent, mode=0o700, exist_ok=True)
+                    os.replace(f, os.path.join(spent, name))
+            except OSError:
+                pass
@@ cmd_commit(), after the retire/leave_offers block @@
             leave_offers(dest, jdir, None if args.no_claim else shared)
+    sweep_offers(working_copy_paths())
```

- An emptied offer moves to `spent/`, the way `forget` moves records to
  `forgotten/`. It is not unlinked.
- The `.tmp` suffix is not in `JOURNAL_SUFFIXES`, so a reader never sees a
  half-written offer.
- It runs inside the commit lock. Only commits write offers.
- It costs one read-only `jj diff` per commit, about 20 ms.

Add these two tests to `tests/lib/python/test_ccjj.py`, next to the offer
tests:

```python
def test_an_ended_peers_offer_ends_once_its_path_goes_clean(repo):
    """A's commit left b.txt offered; A ended. B then committed b.txt, so
    nothing of A's is left in it. B's later Bash change must be claimable."""
    _left_behind(repo)
    _ended(repo, "A")
    _bash(repo, "B", tuid="t3")
    r = repo.run("commit", "-m", "b wholesale", "--also", "b.txt", "--force",
                 sid="B", extra=["--no-claim"])
    assert r.returncode == 0, r.stdout + r.stderr
    _bash(repo, "B", tuid="t4")
    repo.write("b.txt", "A-PERL\nline2\nB-AGAIN\n")
    _bash(repo, "B", tuid="t5")
    r = repo.run("claim", "b.txt", sid="B")
    assert r.returncode == 0, r.stdout + r.stderr


def test_an_ended_peers_offer_still_refuses_while_its_bytes_remain(repo):
    """Safety: B commits something else; b.txt still holds A's Bash bytes."""
    _left_behind(repo)
    _ended(repo, "A")
    _hook_edit(repo, "B", "c.txt", "line1", "BC")
    r = repo.run("commit", "-m", "c only", sid="B", extra=["--no-claim"])
    assert r.returncode == 0, r.stdout + r.stderr
    _bash(repo, "B", tuid="t4")
    repo.write("b.txt", "A-PERL\nline2\nB-AGAIN\n")
    _bash(repo, "B", tuid="t5")
    r = repo.run("claim", "b.txt", sid="B")
    assert r.returncode == 1, r.stdout + r.stderr
    assert "A (ended)" in r.stderr
```

**Checked** on a copy with the repo's own layout, so the tests ran the patched
`ccjj.py`:

- Unpatched: the first test failed with the same refusal the session saw
  ("b.txt changed during the Bash span of session(s) A (ended) …
  `ccjj claim --force b.txt`"). The safety test passed.
- Patched: both passed.
- Patched, whole file: 222 passed, 1 xfailed.

### Also change

- **The label that misled the retro.** In `status_label()` (about line
  2765), change `"left by an earlier commit"` to `"left uncommitted by its last
  commit"`.
- **The docs.** In `docs/cc-jj-sessions.md`, "What `--no-claim` leaves
  behind", change "later commits carry it until the path stops differing from
  `@-`" to "any later `commit-mine`, by any session, drops a path from it once
  that path no longer differs from `@-`".

### Limits and smaller fixes

- A commit made outside `commit-mine` does not sweep. Examples are a human
  `g run ci` or `jj commit` while no peer is live. If the path is changed again
  before the next `commit-mine`, the stale stake stays until the prune.
  Sweeping from `ai_jj_commit` too would close that.
- Today's stopgap needs no code. The stake is "window only", so `ccjj claim
  --force <path>` is correct after reading the diff. `ccjj disown ab5d1454`
  also removes the ended journal. The prune retires it about 2 days after
  10:55 on 2026-11-16.
- Same family: `.cc/FIXME-ccjj-crash-refusal.md`, where a refusal names an
  ended session and gives no next step. Fix 1 there (show the owner state and
  the time of the last record) would also have shown "ended, offer from
  10:55", which explains this case.
- Not tested: `claimable_windows()` merges a stale offer's windows into the
  **owner's** own claim span. That can widen the diff the owner is shown.
  The sweep also removes the stale offer for that case.

---

## 4. One shared test world

**Diagnosis: true.** The engine double rejects any `$` call that no test hook
answers ("no implementation for <event>"; the engine's base handler is
`Promise.reject(new Le("no implementation for "+event))`). So each new engine
call the mod makes breaks every test file whose world lacks it.
`flow.test.tsx` and `modes.test.tsx` each have their own `world()`.

**The helper question: settled by experiment.** `claude plugin test --help`
says it runs "every `*.test.ts` and `*.test.tsx` under dir". In a copy of the
mod:

- `tests/world.tsx`, imported by a test as `./world`, loaded and worked.
- `tests/orphan.tsx`, which throws at load time, was never run. The run
  reported 5 files, which was the four tests plus the probe.
- `tsc -p` checks `tests/world.tsx` too (a planted error was reported).
- Saving a file in `tests/` reloads nothing in live sessions, because the mod
  does not import it.

**But one fixed world will not drop in.** The two worlds differ on purpose:

| Hook | flow | modes |
|---|---|---|
| `prompt.submit` | starts a turn only for prompts in `turnFor` (tests folding into a running turn) | always starts a turn |
| `process.run` | roll tag only | roster, vote-lock failures, roll log |
| `model.complete` | echoes markers to tell openers apart | fixed text |
| `store.get` | always `undefined` | backed by a `Map`, plus `store.set` |

I could not settle whether a second `on()` for the same event overrides the
first or chains to it: the test `$` does not expose engine calls such as
`session.id` to probe directly. So do not build on override order.

**Revised fix.** Create `tests/world.tsx`. It exports a `world($, on, opts)`
factory:

- **Hooks it owns:** the plumbing both files need, and that new engine calls
  keep adding. These are `command.register`, `store.get`/`store.set` (backed by
  a `Map`), `ui.panes`/`ui.open`/`ui.close`/`ui.toast`, `session.id`,
  `session.start`/`session.end`, `turn.start` and `turn.complete`.
- **Hooks it takes as options:** `process.run`, `model.complete` and
  `prompt.submit`, each as a function. Each one has a default, and each file
  passes its own.
- **No import of `../hooks/register`.** A test file that imports the module
  gets its own copy of it (README).
- **All state built inside `world()`.** None at module level. Each test file
  gets its own copy of `world.tsx`, and module state carries across the tests
  in one file.

Add one README line under "Checking a mod": "Only `*.test.ts(x)` files run, so
a shared helper such as `tests/world.tsx` is safe there. Build its state inside
the function: module state carries across the tests in a file."

---

## 5. Global rule: syntax-check Python with `ast.parse`

**Rejected.**

- **The proposed command is weaker.** For a file containing
  `x = 1\nreturn x`, `ast.parse` passes. `compile()` and `py_compile` both
  reject it ("'return' outside function"). Many errors are raised by the
  compiler, not the parser.
- **The harm is nil.**
  - Line 1 of `.gitignore` is `__pycache__`.
  - jj honours it: `jj st` reports a clean working copy.
  - `jj file list bin/__pycache__` matches nothing.
  - `bin/__pycache__/` already holds 10 such `.pyc` files from earlier checks
    (for example `ai-commit-msg`, `akr-chat` and `hermes`). None of them ever
    reached a commit.
  - `bin/` is on PATH, but its subfolders are not.
- **The suggested environment fixes.**
  - `PYTHONDONTWRITEBYTECODE=1` does **not** stop `py_compile`. It still wrote
    `__pycache__/goodcpython-311.pyc`.
  - `PYTHONPYCACHEPREFIX` does redirect it. But set globally, it moves every
    Python bytecode cache on the machine to fix a problem that does not exist.
- **Cost.** A rule in `rcs/claude-user-claude.md` is input on every request in
  every project. This one would be about 35 to 40 tokens, for no protection.

If a session wants a check that writes nothing, the right command is
`python3 -c 'import sys; compile(open(sys.argv[1]).read(), sys.argv[1], "exec")' FILE`.
That does not need a global rule either.
