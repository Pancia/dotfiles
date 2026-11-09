# Adversarial review: four proposed fixes to `ccjj` / `commit-mine`

Date: 2026-11-09. Code reviewed: `lib/python/ccjj.py` as it stood in the shared
working copy that day. Line numbers refer to that version.

## Method and limits

- All behaviour tests ran in throwaway jj repos with `HOME`, `XDG_STATE_HOME` and
  `CC_JJ_JOURNAL` pointed at a scratch folder. The hooks were fired with the same
  payload shape that `tests/lib/python/test_ccjj.py` uses.
- "Variant" means a patched copy of `ccjj.py` in the scratch folder. `~/dotfiles`
  was not changed, apart from this file.
- Real-data figures come from a read-only pass over the live journal, with
  `--ignore-working-copy` on every jj call.
- The scripts are `realdata.py`, `harness.py`, `scenarios.py`, `scen2.py` and
  `scen3.py` in the session scratchpad, under `ccjj-review/`. They disappear at
  reboot.

Not verified:

- The ccjj test suite was not run. There is no `ccjj` test component; the tests
  are part of `lib/python`. None of the prototypes were run against it.
- A real Claude Code session was not used. Hook payloads are simulated.
- The real history of why six sessions drifted is not known. Every `jj commit` op
  has the same description, so the op log does not say which tool made it.
- The PreToolUse design mentioned under proposal 1 was not built or measured.
- The fail-open at `ccjj.py:779` (an unresolved window drops a stake silently) was
  not reproduced. One `jj op abandon` attempt left the window ids resolvable.

## Summary

| # | Proposal | Verdict |
|---|---|---|
| 1 | Per-window stakes | **REJECTED** |
| 2 | Keep window records after `--no-claim` | **CONFIRMED WITH CHANGES** |
| 3 | Report drift for live sessions only | **CONFIRMED WITH CHANGES** |
| 4 | One documented route: read the diff, then `--force` | **CONFIRMED WITH CHANGES** |

A more serious defect than any of the four is in the exit-5 check. See the last
section.

## Proposal 1: false stakes (per-window check). REJECTED

**Diagnosis.** The symptom is real, and the stated cause is half right.
`window_coverage` does use one span per session (`ccjj.py:775-778`). But the idle
gaps are not an artefact of the span. A window runs from the end of the previous
Bash call to the end of this one (`ccjj.py:681-702`, PostToolUse only). Each
window therefore *contains* the idle gap before its own call.

**Why the fix does nothing.** Windows are contiguous, so their union equals the
span. A path that changed at any time between a peer's first and last Bash call is
inside one of that peer's own windows.

- Reproduced: A edits a file with Bash; peer B then makes one unrelated Bash call.
  The base code and the per-window variant refuse identically.
- Real data: 8 sessions with windows. The span gives 107 paths with 65 contested.
  Per-window gives 107 paths with 65 contested. No session's set differs.
- Per-window can only *add* stakes. A path changed and reverted inside a peer's
  span has no net delta, but it does appear in one window. Reproduced: base code
  allows the claim, the variant refuses it.

**Cost.** One jj process per window instead of one per session. On the real
journal one `window_coverage` pass went from 385 ms to 1492 ms. An ordinary commit
makes two passes (`ccjj.py:1335`, `:1532`). The first holds the commit lock, and
peers exit 4 while it is held. `check_new_files_against_disk` makes one more pass
per differing new file, because it passes no `cov` (`ccjj.py:1171`, `:1781`).

**Honesty.** Per-window attribution would be no more honest than span attribution.
Both report "this path changed while this session existed". The stake depends on
timing: if B makes no Bash call after A's edit, the same claim succeeds with no
refusal (reproduced).

**Better fix.** Leave the guard's logic alone and make it say what it knows.

1. Change `ccjj.py:1648-1649`. "is also claimed by" and "therefore includes their
   edits" are false when the only evidence is an overlapping window. Split the two
   evidence classes: "has an Edit/Write record for this path" and "was running when
   this changed; that does not show it wrote this".
2. Keep the refusal for both classes. It is the only thing between exit 5's printed
   `ccjj claim` lines and a misattribution, and
   `test_also_refuses_a_bash_only_peers_path` pins the incident behind it.
3. If stakes must really get narrower, the only route is a pre-call marker, so that
   a window means "during my call". That reverses the decision at `ccjj.py:638`.
   It adds snapshot cost, loses coverage when Post does not fire, and is still not
   attribution, because a long Bash call stays open while peers write.

## Proposal 2: `--no-claim` loses Bash records. CONFIRMED WITH CHANGES

**Diagnosis.** True, and reproduced with the observed error.

- `retire` moves the whole directory (`ccjj.py:1505`, `:2091`).
- `keep_unreplayed` brings back records only (`ccjj.py:2110-2115`).
- `.last` is not restored either, so the next Bash call only sets a baseline. Calls
  with an unchanged working copy write nothing (`ccjj.py:699`).
- The message at `ccjj.py:1621` is false: Bash calls were recorded and then
  archived. It also fires when the opt-in marker is present and windows were simply
  retired.

**A consequence the proposal missed.** The commit also removes A's stake. A leaves
its Bash edit with `--no-claim`. Peer B could not claim that file a moment earlier.
Now B claims it with no refusal and commits A's bytes under B's message, exit 0
(reproduced).

**Why the fix as stated fails.** A `.win` is a whole-copy id pair, so it cannot be
kept "for the paths left behind". Two variants were tested: keep every window, and
keep only windows that touch a left-behind path. Both make the next commit stop
with exit 5 naming `a.txt`, which the previous commit just landed. That is exactly
the failure the `keep_unreplayed` docstring warns about for `.last`. Kept windows
also leave a gap before the next baseline, and `cmd_claim` compares across it
(`ccjj.py:1686-1693`). The contiguity promised at `ccjj.py:730` is already broken
in practice: one real 13-window session is not contiguous, because
`absorb_same_process` deletes `.last`.

**Better fix (prototyped, passes).** Under `--no-claim`, write a separate `.offer`
file holding the left-behind paths and the window list.

- `cmd_claim` uses the offer's windows for those paths.
- `window_coverage` counts a stake only for those paths.
- The exit-5 check skips offers, so `--no-claim` is not asked again on each commit.

Details the prototype found by failing:

- `journal_age_hours` and `has_activity` must count `.offer`. Otherwise the daily
  prune retires a journal holding only offers.
- `keep_unreplayed` must carry offers across later commits.
- Limit offers to `--no-claim`, so that an ordinary commit does not keep a stale
  stake alive.

Result in the prototype: the peer is refused, the next commit is clean, and a later
claim commits correctly.

Also correct the message at `ccjj.py:1621`, whichever fix is chosen.

## Proposal 3: noisy drift warning. CONFIRMED WITH CHANGES

**Diagnosis.** True. `survey` records drift for every journal
(`ccjj.py:1895-1897`), and the comment at `:1892-1894` says this is deliberate. The
six observed sessions are visible in the real journal. All six owners are dead,
with last activity 22 to 48 hours ago where any activity exists. Their bases are
outside the 40-op walk (`ccjj.py:1926`), so no restore point can be named. The
running session was not listed because its base was current; that is correct.

**Why live-only is too blunt.** An ended session's work really can be inside a
stray commit, and drift is then the only signal. Reproduced: an ended session's
edit is swept by a bare `jj commit`. Base code reports the move. The live-only
variant prints "nothing unclaimed in the working copy".

Of the six real sessions, four had records or windows overlapping the paths that
moved. Two had no work at all. Overlap does not prove a sweep.

The proposal is right that the current text is wrong for these sessions. It tells
the agent to report to the user first (`ai/commands/commit.md:86-88`), and offers
an undo that would rewind three live peers.

**Better fix (prototyped, passes).** In `report_drift`, split by liveness.

- Live sessions keep the full report and the undo.
- Ended sessions with records or windows collapse to one line that names no
  culprit and no undo. Ended sessions with no work print nothing.
- The op-log walk runs only for live bases. A full walk on the real repo took
  1.7 s, and an unmatched old base forces a full walk on every audit.

## Proposal 4: dead-end instructions. CONFIRMED WITH CHANGES

**Diagnosis.** True for the document, not for the tool. `ai/commands/commit.md:74-77`
sends every refusal, including a stake refusal, to "the suggested route (`--also`)".
The tool itself correctly says `claim --force` (`ccjj.py:1650`). `--also` refuses
the same paths (`ccjj.py:1280-1296`). In the observed run `claim --force` was the
correct step, and it failed only because of proposal 2.

**"Then `--force`" is ambiguous and dangerous.** The two forces differ.

| Route | Result when a peer also edited the file later (reproduced) |
|---|---|
| `commit-mine --force --also` | Takes the whole file, **including the peer's later edit**. Prints no diff at all. |
| `claim --force` on a Bash-only path | Takes only the narrowed window, so the peer's later edit stays out. The next commit then exits 5 (see below). |
| `claim --force` on a path with your own records | Replaces them with the **whole file on disk**, including the peer's hunk (`ccjj.py:1680`, `:1747`). Reproduced: peer's unfinished line committed under your message, exit 0. |

**Does documenting `--force` defeat the guard?** `--force` is not new; it is in the
tool's text and in `docs/cc-jj-sessions.md:219`. The risk is frequency. 65 of 107
real covered paths are contested, so a documented `--force` becomes the routine
answer.

**Better fix.** Write a decision by case, in `commit.md` and in the refusal text.

- Stake is window overlap only, and every hunk in the printed diff is yours:
  `ccjj claim --force <path>`.
- A peer has an Edit/Write record on the path, or any hunk is not yours: do not
  force. Use `--no-claim` and report it.
- Delete or rename only: `--force --also`, and make the `--also` refusal print the
  diff so that "read the diff" is possible.
- The `--force` help text says "live session" (`ccjj.py:2396`, and
  `docs/cc-jj-sessions.md:219`). The check also counts ended sessions.

## More serious defect: false exit 5 from `commit-mine`

The exit-5 check (`ccjj.py:1335-1340`) tests window coverage and record replay, but
never asks whether the path is still changed in the working copy, or whether a peer
explains the difference. Both cases below are reproduced.

**1. It stops on a file a peer has already committed.** A's span crosses B's
commit, so the tree diff includes B's file. A is told its "changed" file "would NOT
be committed" and is told to claim it. Any commit by any peer can trigger this.

**2. It breaks the main use case.** A and B both use only the Edit tool on one
file. A then makes any Bash call. `mine[p]` lacks B's hunk, so
`mine[p] != working_copy_bytes(p)` and A stops with exit 5. Following the printed
advice leads to a refusal, then `claim --force`, which takes B's unfinished hunk
into A's commit at exit 0. Only `--no-claim` gives the right result.

A variant of the same trap follows a correct `claim --force` when a peer later
edited the file: exit 5 again, and re-claiming would supersede to the whole file.

These false stops are what make `--no-claim` routine, which in turn makes proposal
2's data loss routine. Fix this first.

**Fix (prototyped, passes).** Require `p` to be in the `@-`..`@` delta, at one jj
call. For the `mine[p] != disk` branch, stop only if no live peer has a record on
`p`. With both changes, the peer-committed case and the Edit-only case commit
cleanly, with only A's hunk in the file, and an own Bash half with no peer still
stops at exit 5. The accepted loss: if A has both a Bash half and a peer's record
on one file, the stop no longer fires. That case should print a note.

## Recommended order

1. Filter the exit-5 check (above).
2. `.offer` records and the corrected message (proposal 2).
3. Rewrite the claim refusal and the `commit.md` route by evidence class (proposals
   1 and 4).
4. Split drift reporting (proposal 3).
5. Drop per-window coverage.
