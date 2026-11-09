# Verdict: `commit-mine --also` peer-leak in `lib/python/ccjj.py`

**Both claimed cases are CONFIRMED**, reproduced end-to-end in throwaway jj repos
with `CC_JJ_JOURNAL` pointed at a temp directory. Nothing in `~/dotfiles` or the
real journal was touched.

Code read at `577cf71b4661 ccjj: compare paths by inode, not by case` — i.e.
*after* the inode-comparison commit named in the brief — as it stands in `@-`
(`83700520 ccjj: write up three journal bugs and a fix order`). Line numbers
below are that file's. `jj 0.39.0`.

**Concurrency note.** A peer session added `ccjj forget` to `lib/python/ccjj.py`
mid-investigation (working copy grew 2025 → 2129 lines, hunks at `:797`, `:843`,
`:1868+`, `:1993`, `:2010`). None of the three regions under test moved or
changed — verified by diffing the committed and working-copy versions of the
`--also` check, `claim`'s peer-stake check and `claim`'s delete/rename redirect:
all three byte-identical. The reproduction was re-run against the newer on-disk
file and produced the same four results. Add +6 to every line number below to
locate them in the current working copy.

Reproduction driver: `<scratchpad>/repro.py`, `repro2.py`, `repro3.py`,
`repro4.py` (scratch, will be purged — full transcripts are inlined below).

---

## 1. The code-level asymmetry

It exists in the source, plainly, independent of any runtime test.

### `--also`'s stake check — `cmd_commit`, ccjj.py:1092-1103

```python
        if also and not args.force:
            # --also takes a path WHOLESALE, so a live session's unfinished work
            # in it lands under your message with no hunk-level split. `claim`
            # refuses the identical situation by name; this did not even look.
            contested = sorted({p for p in also for t in other_live_sessions(sid)
                                if p in claims_of(t)})
            if contested:
                die("--also would take these wholesale, but a live session is\n"
                    "  working on them: %s\n"
                    "  Their unfinished work would be committed under your message.\n"
                    "  Re-run with --force only if you are sure."
                    % ", ".join(contested), 1)
```

Two restrictions, both narrowing:

- **Live peers only.** `other_live_sessions(sid)` (ccjj.py:1783-1800) filters on
  `has_activity(d) and session_is_live(d)`. A peer whose owning `claude` process
  has exited fails `owner_alive()` and is simply not in the list.
- **Records only.** `claims_of(t)` (ccjj.py:1488-1496) iterates `load_records()`,
  which reads **`.json` only** (ccjj.py:788-790: `if not name.endswith(".json"):
  continue`). Bash windows (`.win`) are never consulted.

### `claim`'s equivalent refusal — `cmd_claim`, ccjj.py:1446-1464

```python
    # A peer's stake in this path can be an Edit record OR a Bash window of
    # their own -- checking only records let a Bash-only peer's work be claimed
    # and committed under someone else's name with no warning at all.
    cov = window_coverage()
    live = set(other_live_sessions(sid))
    base_dir = os.path.join(journal_root(), repo_key(ROOT))
    peers = [d for d in (os.listdir(base_dir) if os.path.isdir(base_dir) else [])
             if d not in ("archive", sid)
             and os.path.isdir(os.path.join(base_dir, d))]
    others = [s for s in sorted(peers)
              if path in claims_of(s) or s in cov.get(path, ())]
    if others and not args.force:
        die("%s is also claimed by session(s) %s.\n"
            ...
            % (path, ", ".join("%s (%s)" % (s[:8], "live" if s in live else "ended")
                               for s in others), ...), 1)
```

Both restrictions are absent:

- **All peers**, live or not — it enumerates the journal directory itself and
  uses liveness only to *label* the refusal (`"live" if s in live else "ended"`).
- **Records OR windows** — `path in claims_of(s) **or** s in cov.get(path, ())`,
  where `cov` comes from `window_coverage()` (ccjj.py:688-713), built from
  `.win` files.

**Conclusion, from the code alone:** `--also`'s check is a strict subset of
`claim`'s along both axes exactly as claimed. The `:1094` comment ("`claim`
refuses the identical situation by name; this did not even look") describes a
guard that was added but not brought to parity.

There is no compensating check elsewhere in `cmd_commit`. The Bash-window "loose
paths" stop at ccjj.py:1133-1163 **explicitly excludes** `--also` paths
(`if sid in who and p not in also`), and it only looks at *this* session's
windows anyway. The post-commit `survey()` note at ccjj.py:1312-1315 runs after
the commit has landed, and by then the path no longer differs from `@-`, so it
says nothing.

---

## 2. Case 1 — Bash-only peer (live) — **CONFIRMED**

### Setup

Repo with `peer.txt` = `peer original\n` and `mine.txt` = `mine original\n`
committed as `init` (so `@-` holds both).

- `id0 = @` snapshot; peer B writes `peer SECRET-B-WORK unfinished\n` to
  `peer.txt`; `id1 = @` snapshot.
- Session **B**'s journal: one `.win` file `{before: id0, after: id1}` and
  **nothing else** — no `.json`. No `.owner`, so `owner_alive()` → True and B is
  **live**.
- Session **A**'s journal: the same window (A's Bash call spanned the same
  period, which is what makes `claim` applicable to A) plus one genuine `.json`
  Edit record for `mine.txt`, written by driving the real `ccjj record-edit` hook.
- `.jj/ccjj-bash` marker present (checkout opted in), as `~/dotfiles` is.

```
journal A: ['.base', '<ts>.win', '<ts>.json']
journal B: ['<ts>.win']
```

### `ccjj claim` — refuses

```
$ ccjj claim peer.txt -n --session aaaaaaaa-…
-> rc=1
ccjj: peer.txt is also claimed by session(s) bbbbbbbb (live).
  The window's content therefore includes their edits, and claiming
  it would commit their work under your name. Re-run with --force
  only if the diff below is genuinely all yours.
--- a/peer.txt
+++ b/peer.txt
@@ -1 +1 @@
-peer original
+peer SECRET-B-WORK unfinished
```

Note it labels B **`(live)`** — so `other_live_sessions()` *does* see B. The
`--also` check fails purely on the records-only test.

### `commit-mine --also` — takes it, exit 0

```
$ ccjj commit -m "A's work" --also peer.txt --session aaaaaaaa-…
-> rc=0
committed and verified 1 path(s): mine.txt
took 1 path(s) wholesale, unverified: peer.txt
```

```
peer.txt content in the new commit @-: 'peer SECRET-B-WORK unfinished\n'
peer's bytes landed in the commit: True
```

**Exit code 0. The peer's uncommitted bytes are in the commit, under A's
message, with no warning naming B.** Verdict: **CONFIRMED**.

---

## 3. Case 2 — ended peer with records — **CONFIRMED**

### Setup

Same base repo. Peer **B** writes `peer SECRET-B-WORK unfinished\n` to
`peer.txt` **and journals a real `.json` Edit record for it** (via the real
`record-edit` hook). B's session is then marked ended by writing
`.owner` = `99999999\t<lstart>` — a pid that cannot exist, so
`owner_alive()` → False and `session_is_live()` → False. Session A as before.

```
journal A: ['.base', '<ts>.win', '<ts>.json']
journal B: ['.base', '.owner', '<ts>.json']
```

### `ccjj claim` — refuses

```
$ ccjj claim peer.txt -n --session aaaaaaaa-…
-> rc=1
ccjj: peer.txt is also claimed by session(s) bbbbbbbb (ended).
  …
-peer original
+peer SECRET-B-WORK unfinished
```

Labelled **`(ended)`** — confirming B is *not* in `other_live_sessions()`, so
this leg isolates the live-peers-only restriction, exactly as the other leg
isolated the records-only one.

### `commit-mine --also` — takes it, exit 0

```
$ ccjj commit -m "A's work" --also peer.txt --session aaaaaaaa-…
-> rc=0
committed and verified 1 path(s): mine.txt
took 1 path(s) wholesale, unverified: peer.txt

peer.txt content in the new commit @-: 'peer SECRET-B-WORK unfinished\n'
peer's bytes landed in the commit: True
```

Verdict: **CONFIRMED**.

---

## 4. Negative controls — both behave correctly

### Control A — live peer **with** records for the path → refuses

```
$ ccjj commit -m "A's work" --also peer.txt --session aaaaaaaa-…
-> rc=1
ccjj: --also would take these wholesale, but a live session is
  working on them: peer.txt
  Their unfinished work would be committed under your message.
  Re-run with --force only if you are sure.

peer.txt in @- after the run: 'peer original\n'   # unchanged, nothing committed
```

The guard *does* work in the one shape it covers. This rules out the trivial
false positive ("the check is dead code / never fires").

### Control B — no peer at all → succeeds cleanly

```
$ ccjj commit -m "A's work" --also peer.txt --session aaaaaaaa-…
-> rc=0
committed and verified 1 path(s): mine.txt
took 1 path(s) wholesale, unverified: peer.txt

peer.txt in @-: 'A made this via Bash\n'          # A's own bytes, as intended
```

Rules out "`--also` always succeeds regardless".

Summary line from the driver:

```
case1 bash-only live peer : claim rc=1  --also rc=0  peer bytes committed=True
case2 ended peer w/records: claim rc=1  --also rc=0  peer bytes committed=True
ctrlA live peer w/records : --also rc=1  peer bytes committed=False
ctrlB no peer             : --also rc=0  A's bytes committed=True
```

---

## 5. Additional finding — `claim` funnels the user *into* the hole

Not in the original claim, found while building the repro, and it materially
raises the severity.

`cmd_claim`'s whole-path redirects fire at **ccjj.py:1393-1404**, i.e. *before*
its own peer-stake check at **:1446**:

```python
    if status == "removed":
        die("%s was deleted inside a Bash window.\n"
            "  A whole-path change has no hunks to split, so commit it with:\n"
            "    commit-mine -m \"msg\" --also %s" % (path, path), 1)
    if status == "renamed":
        …
            "    commit-mine -m \"msg\" --also %s --also %s"
```

So for exactly the operations `--also` exists for — deletes and renames — the
strong check is **never reached**. `claim` prints the `--also` command and the
weak check is the only one that ever runs.

**Case 3** (live peer *with* records, A deletes the file via Bash): claim
redirects without checking; `--also` then catches it — rc=1. The funnel exists
but the weak check happens to cover this shape.

**Case 4** (live **Bash-only** peer, A deletes the file via Bash): the funnel
fires all the way through.

```
$ ccjj claim peer.txt -n --session aaaaaaaa-…
-> rc=1
ccjj: peer.txt was deleted inside a Bash window.
  A whole-path change has no hunks to split, so commit it with:
    commit-mine -m "msg" --also peer.txt

$ ccjj commit -m "A's work" --also peer.txt --session aaaaaaaa-…      # verbatim
-> rc=0
committed and verified 1 path(s): mine.txt
took 1 path(s) wholesale, unverified: peer.txt

peer.txt in @- after the commit: ''      # deleted in history
on disk: exists=False
```

Following `ccjj`'s own printed advice verbatim committed away a live peer's
uncommitted work — here as a **deletion**, so the bytes are gone from the working
copy as well as absorbed into A's commit. This is the data-loss shape, at exit 0.

### The victim gets no signal

After the case-1 leak, session B's own tooling reports all-clear:

```
$ ccjj audit --session bbbbbbbb-…
-> rc=0
session bbbbbbbb has Bash windows but no edits yet -- nothing of its own to commit until something is claimed
nothing unclaimed in the working copy
```

`ccjj claim peer.txt` as B still prints the diff and exits 0 as though the work
were still B's to commit — but the content is already in `@-`, so a subsequent
`commit-mine` from B would hit the "the commit did not take" wedge
(ccjj.py:1272-1284). Nothing anywhere says a peer took it.

---

## 6. Severity

**Real, silent, and reachable from the tool's own advice — but gated behind a
flag that is only used occasionally.** The leak needs three things to line up:
a genuinely concurrent peer with a stake in one path, that peer's stake being
either window-only or from an ended session, and `--also` being aimed at that
path. The last is the limiter: `--also` is not part of the everyday flow, it is
reached when ccjj tells you to reach for it — a Bash-made delete/rename
(ccjj.py:1396/1403), or a conflicting record (ccjj.py:910). The first two,
though, are not exotic in this repo. The source itself says a Bash-only peer is
"in an opted-in contended checkout ... the likeliest peer there is"
(ccjj.py:1792-1797), and a window's delta is a *whole-working-copy* diff, so any
peer whose Bash window merely spans the same wall-clock period counts as holding
a stake — no intent required. An ended-but-uncommitted peer is the ordinary
residue of a session that exited without committing, which is routine. So this is
worse than a latent edge case and short of a routine trip: **a user doing normal
concurrent work who follows `ccjj claim`'s printed instruction for a deleted or
renamed file will land on it, and will get exit 0, a success message, and no
mention of the peer whose work they just committed or deleted.** It fails open
and fails silent, which for a tool whose entire purpose is "one session's commit
never captures another's" is the worst failure mode available. The fix the plan
already proposes — a single shared `peers_with_a_stake()` used by both
`--also` and `claim` (`.cc/plans/PLAN-ccjj-journal-fixes.md`, Bug 2, fix 1) — is the
right shape; it should also move `claim`'s peer check *above* the
removed/renamed redirects, or the redirect keeps handing users a command that
was never checked.
