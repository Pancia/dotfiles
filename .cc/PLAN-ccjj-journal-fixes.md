# ccjj: three journal bugs, one plan

Three independent bugs in `lib/python/ccjj.py`, all found by hitting them in real
commits. Each was worked around the same way — **hand-deleting a journal record**
— which is itself the finding: no CLI removes one, while two `die()` messages
instruct you to.

**Provenance note.** Bugs 1 and 2 were investigated by subagents that wrote
531- and 596-line reports to a `/private/tmp` scratchpad. **Those files were
purged before this plan was written.** What follows for bugs 1 and 2 is
reconstructed from the session transcript, which captured both root causes, the
primary diff for bug 1, and bug 2's full ranked recommendation — but not their
supporting detail. Bug 3's report survives at 708 lines and should be read
directly if it still exists. This file lives in `.cc/` precisely so it does not
evaporate again.

Confidence is marked throughout: **[verified]** = I read the code or ran it;
**[agent]** = reported and reproduced by a subagent, not independently re-checked;
**[transcript]** = recovered from the session log after the report was lost.

---

## Bug 1 — the poisoned record

**Symptom.** `commit-mine` dies: *"journal record for X is inconsistent: its
recorded pre-edit content does not contain …  Remove the record."*

**Root cause [verified].** `cmd_record_edit` (`:385-399`) assembles one record
from two different payload sources:

```python
"old":      tin.get("old_string"),      # tool_input  — what was ASKED FOR
"new":      tin.get("new_string"),      # tool_input
"original": tres.get("originalFile"),   # tool_response — what the file WAS
```

`anchored_replace` (`:717`) then requires `old ⊂ original`. Nothing enforces
that. Claude Code's Edit tool resolves `old_string` against the file before
applying it, so a literal `🎲` in the request matches a file storing
`🎲`, and the two fields disagree. The mismatch arrives already broken
in the payload; ccjj has no asymmetric decode path of its own.

**Blast radius [agent].** Any `\uXXXX` escape — not `\n`/`\t`, and the matcher is
not fuzzy. A `replace_all` variant misleadingly blames the committed file.

**Sibling bug, same class [agent].** CRLF files fail identically because
`originalFile` arrives LF-normalized, and fail with the *wrong* message
(*"you must have used Bash"*).

**A test that cannot fail [verified].** `tests/lib/python/test_ccjj.py:259`
hand-builds its record:

```python
repo.record("S1", "w.txt", old="beta", new="BETA",
            original="alpha\r\nbeta\r\ngamma\r\n")
```

If `originalFile` really arrives LF-normalized, no real hook can produce that
record. The test asserts on a shape the system cannot generate, so it passes
while the real path is broken. Same family as the circular-test lesson already
recorded in `CLAUDE.md` from the `llm_output` work.

**Fix [transcript].** `tool_response` already echoes `oldString` / `newString` /
`replaceAll`, and those are substrings of `originalFile` *by construction*.
Record those instead, so the invariant holds structurally rather than by hope:

```python
def applied(res_key, in_key):
    v = tres.get(res_key)
    return v if isinstance(v, str) else tin.get(in_key)

"old":          applied("oldString", "old_string"),
"new":          applied("newString", "new_string"),
"content":      applied("content", "content"),
"replace_all":  bool(tres["replaceAll"]
                     if isinstance(tres.get("replaceAll"), bool)
                     else tin.get("replace_all")),
```

Plus: a loud replay-time reconciler for records already on disk, a CRLF
counterpart, and a record-removal command. Reported 88/88 existing tests green.

---

## Bug 2 — the claim/commit cycle, and a weaker escape hatch

**Symptom.** A path with both Edit/Write records and a Bash-made change cannot be
committed by any verified route.

**It is a cycle, not a dead end [agent].** `ccjj commit` exits 5 saying *run
`ccjj claim`*; `claim` exits 1 saying *commit them first*. `--force` does not
apply and `audit` reports all-clear. It also fires with **no Edit/Write at all** —
claim #1's own record blocks claim #2 — so it hits ordinary Bash-only work on the
second change to any file.

**The escape is weaker than the refusal [agent, NOT re-verified].** `--also`'s
peer-stake check is strictly weaker than `claim`'s: records only, live peers only.
The agent reports reproducing `--also` **silently committing a peer's uncommitted
work** in the two cases `claim` refuses by name. The source comment at `:1112`
reads *"`claim` refuses the identical situation by name; this did not even look"*
— past tense, so a check was added at some point; the claim is that it is still
the weaker one. **This is the single most important unverified claim here and
should be reproduced before anything ships.**

**Fix, in this order [transcript].**

1. **One shared `peers_with_a_stake()`** used by both `--also` and `claim`. A bug
   fix, not a feature — it closes a path that commits another session's work at
   exit 0. Must land first, because (3)'s safety argument rests on it.
2. **Byte-verify `--also` content paths.** Small, purely additive.
3. **Superseding claim** — `claim` replaces the path's records with one
   whole-span `Write` record instead of refusing. Removes the cycle, restores the
   post-commit byte check, and handles interleaved ordering. Reported 8 shapes
   correct, 86/88 (2 deliberate).
4. **Rewrite the residual refusals** so each names its escape.

The report argued explicitly *against* "leave it alone and document it" — normally
right for this tool, since most guards are refusals holding back corruption — on
three grounds: the refusal is a cycle with no safe exit, the documented way out is
measurably less safe than what it refuses, and it fires on ordinary work.

---

## Bug 3 — the journal resurrects deleted files

**Symptom.** A file created and then trashed inside one session still appears in
the scoped diff as a fresh add, because the `Write` record outlives it.

**Root cause [verified].** `build()` (`:934-1012`) never touches the filesystem.
Line 943 seeds only from `@-`:

```python
content = jj("file", "show", "-r", "@-", fs(path)).stdout if path in present else b""
```

A `Write` record for a path absent from `@-` is then adopted wholesale. The
journal is append-only, Bash deletions are journaled nowhere, and nothing
subtracts. `--also` already has exactly the guard records lack (`:1088`).

Deletion *is* handled — but only at the edges: `--also` validates existence
(`:1087`), and `claim` refuses a window-deleted path (`:1393`). The default
replay path asks nothing. The comment at `:108` shows records naming deleted
files were considered at the *path-containment* layer — "only its ancestors need
to exist" — so they resolve rather than fail. Resolving and deciding whether to
replay are separate questions; only the first was answered.

**The reported case is the LOUD variant. Two silent ones are worse [agent].**

| Case | Result |
|---|---|
| Write + delete | rc=1, wedged, misdiagnosed; no CLI recovers (`--also` refuses, `claim` refuses, `disown` destroys the real work too) |
| **Edit + delete** | **rc=0, "committed and verified", file silently resurrected** |
| **Write / delete / recreate** | **rc=0, the superseded version beats what is on disk** |

The third is the dangerous one: a version you deleted — a probe against
production, a scratch credential — wins over current disk content, silently,
reported as verified.

Bash windows catch cases 2 and 3 but **not** create-and-delete, whose window
delta is net-zero. Same for `audit`. And in case 2 the record causing the bug
also suppresses `audit`'s report of it.

**Two verification holes [verified / agent].**

1. The post-commit byte check verifies **transcription of the payload, not
   correspondence to reality** — already documented in the source at `:810-813`,
   about a sibling double-replay bug.
2. It cannot distinguish *absent* from *empty*, so a zero-byte throwaway is
   reported "committed and verified" while not being in the commit. **[agent]**

**Fix [agent].** An existence filter **before** `build()` — ordering is
load-bearing for composing with bug 1 — plus a narrow content reconcile
restricted to paths absent from `@-`. Reported: cases 1/2/3/4a/6a fixed, the
98-test ccjj suite passes unchanged (baseline `cmds test python` = 256 passed).

---

## The thing all three share

`ccjj forget <path>` (or `drop-record`) does not exist. Two `die()` messages
already tell you to remove a record. All three bugs were worked around by hand.
All three reports flagged it independently. **This is the highest-leverage single
addition**, and it is also the recovery route for any future journal corruption.

## Suggested order

1. `peers_with_a_stake()` — safety bug, and bug 2's step 3 depends on it
2. `ccjj forget <path>` — unblocks manual recovery for all three
3. Bug 1's `applied()` — makes the replay invariant structural
4. Bug 3's existence filter, before `build()`
5. Byte-verify `--also`; superseding `claim`
6. The test work: invert `test_claim_refuses_when_the_session_also_edited_the_file`,
   fix the CRLF test so it uses a hook-producible record, and add the missing
   three lines to `test_stop_fires_when_a_journaled_path_also_changed_via_bash`
   (it never runs the `ccjj claim` it advertises — that omission is what let bug 2
   ship)

**Before any of it:** independently reproduce the `--also` peer-leak (bug 2). It
is the most serious claim in this document and the only load-bearing one taken on
report alone.
