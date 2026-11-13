# Review: seven retro proposals from the ~/Cloud reorganization (2026-11-12)

Scope: try to refute each proposal. No project file was changed. All behaviour
tests ran in throwaway copies under the session scratchpad. This repo is public,
so private folder names and account details are left out; examples use generic
paths.

Each claim is marked **[tested]** (I ran it) or **[reasoned]** (I read the code
or a document and did not run it).

## Ranking (most solid first)

| Rank | Item | Verdict |
|------|------|---------|
| 1 | 2. Point the global CLAUDE.md at ~/Cloud/CLAUDE.md | Confirmed |
| 2 | 3. Trash ~/.config/hermes/commands.py | Confirmed |
| 3 | 7. ccjj: skip ignored journal paths | Confirmed, with changes |
| 4 | 1. Add ~/projects to the search rule | Changed |
| 5 | 4. safe_merge.py trailing-slash rule | Changed (a worse defect found) |
| 6 | 5. Name commit-mine in the vault's post-commit paragraph | Rejected: already done |
| 7 | 6. One line saying rmdir goes through trash | Rejected (a worse defect found) |

---

## 1. Add ~/projects to the "search before you move" rule — CHANGED

Location: `~/.claude/CLAUDE.md:172` (section "File Deletion").

**Diagnosis: true. [tested]** The rule searches `~/dotfiles ~/Vaults ~/.config
~/Library/LaunchAgents`. With `~/projects` added, the proposed command finds all
four missed files when searched by the moved folder's name:
`hermes/Sources/Hermes/Services/CommandLoader.swift`,
`ereshkigal/bin/import-audio.fish` and `import-all-audio.fish`,
`hypnosis-audio-generation/TO_GENERATE`, `sekhmet/native-host/ytdl_host.py`.
Note that CommandLoader.swift spells the path `~/ProtonDrive/...`, not
`~/Cloud/...`, so searching by name (not by full path) is what catches it.

**Cost: small. [tested]**
- `~/projects` is 11 GB and 34 entries. `rg` honours `.gitignore`, so
  `node_modules` and `.build` inside git repos are already skipped.
- One non-git project has a 35,000-file `.venv`. That is 74% of all files `rg`
  walks under `~/projects` (47,238 total). It doubles the time.
- Timings, warm cache: no excludes 0.9-1.1 s; with `-g '!.venv'` 0.14-0.37 s.
  The existing four roots take about 0.5 s.
- `-g '!.venv'` alone gives the same hit list as the three proposed excludes.
  `node_modules` and `.build` excludes are harmless but add nothing today.
- `rg` does not follow symlinks by default. `~/projects` holds links into
  ProtonDrive (for example an archived project's `journals` link). Never add
  `-L`/`--follow`: it would walk into the cloud folder and download files.

**Worse defects in the same rule. [tested]**
1. The rule says "a script". The session's misses were **folders**. An agent
   moving a data folder can read the rule as not applying.
2. `rg` never sees **symlink targets**. Home links such as `~/Media`,
   `~/MediaBoard`, `~/private`, `~/TheArchive`, `~/transcripts`, `~/Developer`
   point into the cloud folder, and links inside projects do too. Moving the
   folder breaks them silently. `find ~ -maxdepth 4 -type l -ilname '*NAME*'`
   finds them in about 0.5 s and downloads nothing.
3. `~/Cloud/CLAUDE.md:24-25` already carries a copy of this command, with
   `~/projects` but without the `.venv` exclude or the symlink check. Two copies
   will drift; keep them in step.

**Proposed wording** (replaces line 172):

> Before you move, rename or delete a script or a folder, search for its name,
> not its topic or its full path:
> `rg -l -F --hidden <name> ~/dotfiles ~/Vaults ~/.config ~/projects ~/Library/LaunchAgents -g '!.venv'`.
> Also check `crontab -l`, and find symlinks that point at it:
> `find ~ -maxdepth 4 -type l -ilname '*<name>*' 2>/dev/null`. Callers often
> `cd` first and use a relative path.

Apply the same command to `~/Cloud/CLAUDE.md:25`.

---

## 2. Point the global CLAUDE.md at ~/Cloud/CLAUDE.md — CONFIRMED

**Diagnosis: true. [tested]** Three headless Claude Code runs in a scratch tree
(`proj/` as the start folder, `proj/sub/CLAUDE.md` and a sibling
`outside/CLAUDE.md`, each with a unique codeword):

| Action | `proj/sub/CLAUDE.md` (under start folder) | `outside/CLAUDE.md` (not under it) |
|--------|------|------|
| Bash `mv` of a file in each folder | not loaded | not loaded |
| Read tool on a file in each folder | loaded | not loaded |
| Write tool, new file in each folder | loaded | not loaded |

So a session that starts in the vault or in `~/dotfiles` **never** loads
`~/Cloud/CLAUDE.md`, whatever tool it uses. Even a session started in `~/Cloud`
would not get a nested file through `mv`. The reorganization was done with
Bash `mv`, so nothing would have loaded it.

**Right home: yes.** The global section "Cloud-only files in ~/Cloud"
(`~/.claude/CLAUDE.md:238-240`) is the only text every session sees, and it is
already about this folder. `~/Cloud/CLAUDE.md` is a local file (flags `-`, not
`dataless`), so reading it downloads nothing.

**Proposed wording** (append to that section):

> Before you move, add, rename or delete anything under `~/Cloud` (also reached
> as `~/ProtonDrive` and `~/Library/CloudStorage/ProtonDrive-*`), read
> `~/Cloud/CLAUDE.md`. Claude Code does not load it for you: a nested CLAUDE.md
> loads only when Read, Edit or Write touches a file under the session's start
> folder, and never for Bash.

**What it breaks:** nothing. **Smaller fix:** none; this is one sentence.
A stronger but larger option is a PreToolUse Bash hook that prints the file
when a command names `Cloud` or `ProtonDrive`. Not needed now.

---

## 3. Trash ~/.config/hermes/commands.py — CONFIRMED

**Diagnosis: true. [tested]**
- The running Hermes is the Swift binary `~/.local/bin/hermes` (launchd agent
  `org.pancia.hermes`, one process). `CommandLoader.swift:5-15` reads
  `~/.config/hermes/commands.json`, then the bundled `commands.json`. Nothing
  in the Swift source names `commands.py`.
- `commands.json` is a hard link of `~/dotfiles/rcs/hermes-commands.json`
  (same inode), deployed by `rcs/MANIFEST:39`. `commands.py` is not in the
  MANIFEST, and the rcs-sync records do not mention it, so rcs-sync will not
  re-create or complain about it.
- `commands.py` was deployed from `rcs/hermes_commands.py`, which commit
  `61c30fcb` (2025-12-26) deleted when the Python Hermes was replaced. The
  `__pycache__` file is dated 2025-12-25: the last run of the old app.
- `rg -F commands.py` over `~/dotfiles ~/Vaults ~/.config ~/Library/LaunchAgents
  ~/.hammerspoon ~/projects` finds only the file itself and this session's own
  review report. No hammerspoon, crontab or LaunchAgent use. No Python process
  for Hermes is running.

**Fix:** `trash ~/.config/hermes/commands.py ~/.config/hermes/__pycache__`.
**Breaks:** nothing found. **Worse defect:** none.

---

## 4. safe_merge.py: trailing '/' should mean "inside" — CHANGED

File: `~/Cloud/.cc/scripts/safe_merge.py` (82 lines).

**Diagnosis: true, but the root cause is wider. [tested]** Lines 64-66 strip the
slash for a folder source, so `src/folder -> dst/` merges the folder's entries
loose into `dst/`. This matches the docstring (lines 8-10), so it was a usage
error against documented, surprising behaviour.

The worse defect is that **the dry run prints only a count** (`would move: 1`).
`move()` prints nothing per entry. So the preview could not show where the
entries would land, and nobody could catch the mistake before `--run`.

**Other defects found, all reproduced in a scratch copy:**

| Case | What happens now |
|------|------------------|
| Two ops lines target the same name | Dry run: `would move: 2`, no clash. Run: 1 moved, 1 CLASH. The dry run does not track its own planned targets. |
| Destination parent is a file | Dry run: `would move: 1`. Run: uncaught `FileExistsError`. |
| Folder into its own subfolder (`a -> a/b/new`) | Dry run: `would move: 1`. Run: uncaught `OSError EINVAL`. |
| Any error mid-run | Traceback. Earlier ops are done, later ones are not, and no summary prints. With no per-op output there is no record of what moved. |
| Case-only rename of a folder (`Docs -> docs`) | Every child reported as a CLASH; nothing renamed. |
| Absolute or `..` destination | `os.path.join` lets it escape `~/Cloud`; a file moved to a folder outside. Moving out of `~/Cloud` downloads cloud-only files. |
| Race | `os.rename` silently replaces an existing file. A name that appears between `lexists` and `rename` (sync client, another writer) is overwritten. `renamex_np(RENAME_EXCL)` refuses instead [tested on APFS in scratch; **not tested on the Proton File Provider folder**]. |
| Merge leftovers | `.DS_Store` is skipped, so each merged source folder stays behind, not empty; plain `rmdir` on it then fails. |

`lexists` for case-insensitive clash detection is correct on this APFS volume
[tested: `Docs` vs `docs` clash].

**What the proposed rule breaks. [tested + reasoned]** The docstring today tells
users to write `dst/<name>/` in full to keep the name. Under the new rule that
form nests twice: `a/m -> D/i/m/` becomes `D/i/m/m` [tested]. Three ops files
sit beside the script (`pass1.tsv`-`pass3.tsv`). I did not read them (they are
under `~/Cloud` and not on my list). Before changing the rule, check them for
folder lines ending in `/`, or never re-run them with the new script. With
per-op output the dry run now shows the double nesting, so the risk becomes
visible.

**Revised fix** (sketch tested in scratch, all cases above pass):
1. A trailing `/` means "inside dst, keeping the name", for files and folders
   (as proposed). No slash: the path it becomes, renamed or merged.
2. Print every planned move, in the dry run and the run.
3. Track planned targets in a lower-cased set, so the dry run sees clashes
   between ops lines.
4. Catch `OSError` per op, record it as ERROR, continue, print a summary, and
   exit 1 on any error.
5. Refuse a destination outside `~/Cloud` and a folder moved into itself.
6. Handle a case-only rename with a plain `os.rename`.
7. Rename with `renamex_np(..., RENAME_EXCL)`; on `ENOTSUP`/`EINVAL` fall back
   to the current check-then-rename. Test it once on a small cloud-only item
   before relying on it.

Core of the change (full tested sketch in the appendix):

```python
if dst.endswith("/"):
    d = os.path.join(d, os.path.basename(s))     # inside, keep the name
...
print(f"{'MOVE' if RUN else 'would'}  {rel(s)}  ->  {rel(d)}")
```

**Proposed line for `~/Cloud/CLAUDE.md`** (Safety rules, after line 15):

> - To move or merge many entries, use `.cc/scripts/safe_merge.py OPS_FILE`:
>   run it once without `--run` and read every line it prints. It never
>   overwrites and reads no file contents.

---

## 5. Name commit-mine in the vault's post-commit paragraph — REJECTED (already done)

**[tested]** `~/Vaults/the-akashic-records/CLAUDE.md:302` (uncommitted edit by
another session) already says: `/cc:commit` runs the hook after every route,
`commit-mine` included; "A bare `jj commit` or a direct `commit-mine` does not
run it (`commit-mine` prints a reminder)"; run it by hand in the background,
because it can take minutes and a kill mid-bundle leaves a stale lock.

This matches `ccjj.py:1786-1799` (`note_post_commit_hook`: never run, print a
reminder; reasons: minutes-long backup, 120 s Bash kill, stale lock, double run
under `g run ci`) and `~/dotfiles/ai/commands/commit.md:57-58, 261-270`.
No further wording is needed. The brief's snapshot of that file predates the
edit.

---

## 6. One sentence: empty folders also go through `trash` — REJECTED

**Diagnosis: partly true. [tested]** The session ran `rmdir` twice, on two empty
folders. The user's report was "it was about rm being dangrous". Nothing in
`~/.claude/settings.json` hooks or deny rules mentions `rm`/`rmdir`, so the
warning most likely came from the auto-mode classifier [reasoned]. The
transcript does not record the warning itself.

**Why reject:** `rmdir` cannot lose data; it fails on a non-empty folder. A
CLAUDE.md line does not change what the classifier warns about. The value is
close to zero. If a line is wanted anyway, fold it into the existing first
sentence as a clause ("files and folders, empty or not") rather than a new
sentence.

**Worse defect in the same text. [reasoned, not tested under ~/Cloud]**
`trash` (`~/.config/fish/functions/trash.fish:111-129`) moves anything not under
`/Volumes` into `~/.Trash` with `mv`. That is outside `~/Cloud`.
`~/Cloud/CLAUDE.md:13-15` says moving anything out of `~/Cloud` downloads it.
So `trash` on a cloud-only file or folder downloads all of it before it is
deleted, and `~/Cloud/CLAUDE.md:28` ("Delete with `trash`, never `rm`") directs
agents to do exactly that. Test once on one small cloud-only file (watch
`stat -f %Sf` and disk use), then either keep a trash folder inside `~/Cloud`
(a `mv` there downloads nothing) or add a line: check
`find X -flags +dataless` before trashing anything in `~/Cloud`.

**Follow-up 2026-11-13: tested, confirmed.** A throwaway 3 MB file was written
to the cloud folder's `scratch/`, uploaded (`fileproviderctl evaluate`:
`isUploaded = 1`), and evicted with `FileManager.evictUbiquitousItem` (flags
`compressed,dataless`, 0 blocks; `fileproviderctl` on this macOS has no `evict`).
`trash` then took 9 s, and the copy in `~/.Trash` had no `dataless` flag and
5,864 blocks: fully downloaded. `~/.Trash` itself cannot be listed (TCC), but
`stat` on the exact path from `trash list --json` works.

---

## 7. ccjj: skip ignored journal paths — CONFIRMED, with changes

File: `~/dotfiles/lib/python/ccjj.py`, `cmd_commit` (line 1404 on).

**What a real commit would have done. [tested]** Scratch jj repo, colocated,
real global gitignore (`core.excludesFile` = `gitignore_global`, line 8 ignores
`.cc/private/`; jj 0.39 honours it). A Write into `.cc/private/reports/` plus one
normal Edit:

- `commit --diff --no-claim`: exit 0, and the diff **prints the ignored file's
  whole content**.
- Real `commit`: `build()` makes a payload, `jj commit --tool` selects nothing
  for the ignored path, the byte check at `ccjj.py:1717-1731` fails, the
  operation is rolled back, exit 1: "the commit did not take for: <path> ...
  Most likely ... something outside this session already committed them". The
  message gives the wrong cause, but it does suggest `ccjj forget`.
- Ignored path as the session's only record: `--diff` exit 0; commit exit 2,
  "the commit was empty", rolled back, journal kept. Every later commit fails
  the same way until `ccjj forget`.

The existing test `test_an_empty_payload_jj_did_not_take_is_rolled_back`
(`tests/lib/python/test_ccjj.py:354`) uses an ignored file as its vehicle and
pins the fail-closed result.

**Why the fix belongs there:** `.cc/private/` is where the global CLAUDE.md
sends private material, so this recurs in every repo. And
`ai_jj_commit.fish:206-208` feeds `ccjj commit --diff` output to the model that
writes the commit message: the private file's content goes into that prompt,
the message may describe a file that cannot be committed, and the real commit
then fails after the model call.

**Revised fix (patch tested):** after `check_new_files_against_disk(...)`
(line 1538), drop a path from `mine` only when **both** views agree: jj does
not track it in `@` (the fresh pin already snapshotted), and
`git check-ignore --no-index` says it is ignored. A new file over jj's size
limit is untracked but not ignored, so it still fails closed [tested]. A
non-colocated repo has no `.git`, so nothing is dropped.

```python
check_new_files_against_disk(mine, present, sid)
for p in ignored_new_paths(mine, present):
    del mine[p]
    print("note: skipping %s: an ignore rule covers it, so jj does not\n"
          "  track it. It is left out of this commit." % p, file=sys.stderr)

def ignored_new_paths(mine, present):
    new = [p for p in mine if p not in present]
    if not new or not os.path.exists(os.path.join(ROOT, ".git")):
        return []
    tracked = set(jj("file", "list", "-r", "@", "--ignore-working-copy").stdout
                  .decode(errors="surrogateescape").splitlines())
    cand = [p for p in new if p not in tracked]
    if not cand:
        return []
    r = subprocess.run(["git", "-C", ROOT, "check-ignore", "--no-index", "-z", "--stdin"],
                       input="\0".join(cand).encode(errors="surrogateescape"),
                       capture_output=True)
    hit = set(r.stdout.decode(errors="surrogateescape").split("\0")) if r.returncode == 0 else set()
    return sorted(p for p in cand if p in hit)
```

Results with the patch [tested]:
- Session case: `--diff` exit 0, no ignored content in the diff, one note line;
  real commit exit 0, the normal edit committed.
- Size-limit file: still "did not take", exit 1.
- Ignored path as the only record: "nothing to commit", exit 2, journal kept.
  The records are retired by the next real commit. (My first note text said
  "retired with this commit", which is false in this case; hence the wording
  above.)
- Full suite (`tests/lib/python/test_ccjj.py`, copied): **196 passed,
  1 xfailed**, after one test change.

**What it breaks:** it reverses a pinned behaviour. The test above must move to
a non-colocated repo (`jj git init --no-colocate`) to keep pinning the
empty-payload guard, since in a colocated repo the ignored file is now skipped
before that guard. Add a new test for the skip and one for the size-limit case.

**Smaller alternative** (if you prefer to keep fail-closed): in the "did not
take" message, name "ignored by .gitignore" as a cause beside the current one,
and add a pre-commit check that calls `refuse(..., 1)` for ignored new paths,
so `--diff` exits nonzero and `ai_jj_commit` stops before the model call. The
private content would still appear in the `--diff` output, so I recommend the
skip.

---

## Side effects of this review

- Nothing in `~/dotfiles`, the vault or `~/Cloud` was edited apart from this
  report. `git -C ~/dotfiles status --porcelain -- tests lib` is clean.
- One scratch test imported `~/dotfiles/tests/lib/python/test_ccjj.py`, so
  Python refreshed the ignored `tests/lib/python/__pycache__/`.
- Scratch copies (lost at reboot): `.../scratchpad/sm/` (safe_merge),
  `.../scratchpad/ccjj7/` (ccjj patch and tests), `.../scratchpad/nested/`
  (CLAUDE.md loading).

## Appendix: tested safe_merge.py sketch

```python
#!/usr/bin/env python3
"""Move files/folders inside ~/Cloud without overwriting, nesting or reading contents.

Usage: safe_merge.py OPS_FILE [--run]
OPS_FILE lines: <src>\t<dst>   (paths relative to ~/Cloud)
  - dst ends with '/': src goes INSIDE dst and keeps its name (like mv).
  - dst has no '/': it is the new path. A folder is renamed to it, or merged
    into it entry by entry if a folder of that name already exists.
An existing target name (any case) is a CLASH: reported and left in place.
Every planned move is printed, so the dry run shows where each entry lands.
Without --run it only prints what it would do.
"""
import ctypes
import os
import sys

ROOT = os.path.realpath(os.environ.get("SM_ROOT") or os.path.expanduser("~/Cloud"))
RUN = "--run" in sys.argv
_libc = ctypes.CDLL(None, use_errno=True)
planned = set()          # targets taken by earlier ops in this plan (lower-case)
moved, clashes, errors = 0, [], []


def rel(p):
    return os.path.relpath(p, ROOT)


def taken(p):
    # The filesystem is case-insensitive, so lexists also catches case variants.
    return os.path.lexists(p) or p.lower() in planned


def rename_excl(s, d):
    if _libc.renamex_np(s.encode(), d.encode(), 0x4) == 0:   # RENAME_EXCL
        return
    e = ctypes.get_errno()
    if e not in (45, 22):            # ENOTSUP, EINVAL: no RENAME_EXCL support here
        raise OSError(e, os.strerror(e), d)
    if os.path.lexists(d):           # fallback keeps the old check-then-rename race
        raise OSError(17, "File exists", d)
    os.rename(s, d)


def move(s, d):
    global moved
    if taken(d):
        clashes.append((s, d))
        return
    parent = os.path.dirname(d)
    if os.path.lexists(parent) and not os.path.isdir(parent):
        errors.append(f"{rel(s)} -> {rel(d)}: parent is not a folder")
        return
    print(f"{'MOVE' if RUN else 'would'}  {rel(s)}  ->  {rel(d)}")
    if RUN:
        try:
            os.makedirs(parent, exist_ok=True)
            rename_excl(s, d)
        except OSError as e:
            errors.append(f"{rel(s)} -> {rel(d)}: {e.strerror}")
            return
    planned.add(d.lower())
    moved += 1


def merge(s, d):
    if not taken(d):
        move(s, d)  # plain rename of the whole folder: nothing to merge into
        return
    if not os.path.isdir(d) or os.path.islink(d):
        clashes.append((s, d))
        return
    for name in sorted(os.listdir(s)):
        if name == ".DS_Store":
            continue
        cs, cd = os.path.join(s, name), os.path.join(d, name)
        if os.path.isdir(cs) and not os.path.islink(cs):
            merge(cs, cd)
        else:
            move(cs, cd)


def inside_root(p):
    return p == ROOT or p.startswith(ROOT + os.sep)


def main():
    ops = [l.rstrip("\n").split("\t") for l in open(sys.argv[1]) if l.strip() and not l.startswith("#")]
    for src, dst in ops:
        s = os.path.normpath(os.path.join(ROOT, src))
        d = os.path.normpath(os.path.join(ROOT, dst))
        if not (inside_root(s) and inside_root(d)) or s == ROOT:
            errors.append(f"{src} -> {dst}: outside ~/Cloud")
            continue
        if not os.path.lexists(s):
            print(f"MISSING  {src}")
            continue
        if dst.endswith("/"):
            d = os.path.join(d, os.path.basename(s))
        is_dir = os.path.isdir(s) and not os.path.islink(s)
        if s != d and s.lower() == d.lower():        # case-only rename
            print(f"{'MOVE' if RUN else 'would'}  {src}  ->  {rel(d)}  (case only)")
            if RUN:
                os.rename(s, d)
            continue
        if is_dir and (d + os.sep).lower().startswith(s.lower() + os.sep):
            errors.append(f"{src} -> {dst}: folder into itself")
            continue
        (merge if is_dir else move)(s, d)
    print(f"{'moved' if RUN else 'would move'}: {moved}")
    for s, d in clashes:
        same = ""
        if os.path.isfile(s) and os.path.isfile(d):
            same = " (same size)" if os.stat(s).st_size == os.stat(d).st_size else " (DIFFERENT size)"
        print(f"CLASH    {rel(s)}  ->  {rel(d)}{same}")
    for e in errors:
        print(f"ERROR    {e}")
    sys.exit(1 if errors else 0)


main()
```

Known limit of the sketch: if an earlier op in the same plan renames a folder to
X, a later op that merges into X shows a CLASH in the dry run but merges in the
real run (the dry run cannot list a folder that does not exist yet). This errs
toward caution.
