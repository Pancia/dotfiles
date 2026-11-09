# PLAN: tab-organize categorization consistency

Status: **items 1–5 implemented 2026-07-28.** Remaining: `taxonomy.md` (deferred,
matching unsolved), the FIFO half-apply fix, and malformed-JSON abort.
Trigger: tabs misfiled by `plan-20260727-215141.md` (executed 2026-07-27)
Revised 2026-07-28 after adversarial review — the original Mode B diagnosis was
wrong; see that section. Proposals reordered accordingly.

**Post-implementation code review (2026-07-28)** found and fixed two criticals,
both reproduced with a stub `claude` on PATH:

- A single non-dict JSON line on stdout **hung `plan` forever** — `ev.get()`
  raised, the exception escaped to `finally: proc.wait()`, nothing drained
  stdout so the child blocked on a full pipe, and because `stop_event.set()` ran
  *after* `proc.wait()` the ticker kept painting. Indistinguishable from a slow
  model. Fixed: total field walk, non-dict guard, `proc.kill()` on the exception
  path, bounded `proc.wait(timeout=30)`.
- **`is_error` results were written to disk as plans.** The flag was only
  consulted to decide whether to use `result`; on error `final` stayed None and
  the deltas fallback returned the model's apology text, exit 0. Fixed: surface
  and exit 1, plus refuse to write a plan containing no commands.

Also fixed: string tab ids (passed the state check, inverted coverage, broke
`chrome.tabs.remove`), `close_tabs` with no ids (crashed `execute` after the
recovery file was written), titles with embedded newlines forging coverage
candidates (latent — zero live titles affected — fixed at the source in
`build_summary`), the `.input.txt` sidecar being orphaned by both archive paths,
missing `state.json` silently disabling both validation and the recovery file,
a self-contradicting multi-window warning, and a recovery file written before
the FIFO existence check.

**Implementation notes.** Plans are now headings + JSON only; titles are
rendered from `state.json` by `check` / `execute --dry-run`. Decision on the
open trade-off in item 3: separation chosen — the rendered view is mechanically
reproducible, the model's prose was not. First run under the new prompt emitted
6 commands, every heading naming an *existing* group, and picked up the
Stationbreak tab the original run dropped. Coverage check: 15 candidates in, 15
covered, zero dropped.

## Investigation summary

Every command that reached the extension was applied faithfully. Verified
against `browser-sync/logs/2026-07-27.jsonl` and `state.json`:

- **179 fenced blocks, 179 parsed clean, 179 `COMMAND_OK`, 0 `COMMAND_ERROR`.**
- No tab id appears in both `close_tab` and `group_tabs`, none in two
  `group_tabs`, no duplicate `(title, window)` pairs.
- Every listed `(tabId)` in the plan prose matches that tab's real title in
  `state.json`. No id/title shuffling.

**Caveats on that evidence** (raised in review, and fair):

- The originally quoted "552 of 552 tabs placed as planned" does not reproduce —
  re-running it a day later gives 561 ids / 548 in place / 12 tabs gone / 1
  moved (that one manually ungrouped by the user, per the log). `state.json` is
  rewritten on every browser event, so the denominator shrinks continuously.
  The conclusion holds; the three-digit precision was never real.
- `state.json` and `COMMAND_OK` are two views of the **same** extension event
  stream, not independent confirmation. A systematic bug in the extension's
  event handling would be invisible to both.
- The check enumerates only JSON blocks that *parse*, so it is structurally
  blind to a malformed block or a tab the model never emitted (Mode D).

So the accurate claim is narrower than "the pipeline is not at fault": commands
that reached the extension were applied faithfully. The misfiling was written
into the plan by the model. Modes:

### Mode A — medium beats subject

The model classifies on format cues in the title rather than what the tab is
about.

| Tab | Landed in | Should be |
|---|---|---|
| `"Mary did you know?" FINISHED CHRISTMAS ANIMATION` | `anime essays` | `faith` |
| `Hans Zimmer ... Part The Red Sea \| The Prince of Egypt` | `music` | defensible, but split from its sibling |
| `God Speaks To Moses (Burning Bush) \| The Prince of Egypt` | `entertainment` | defensible, but split from its sibling |

### Mode B — the model competes with existing groups

**Corrected 2026-07-28 after adversarial review. The original diagnosis below
was wrong and is kept for the record.**

> ~~Each `group_tabs` section is generated independently, so identical content
> diverges — a coin-flip repeated in two places of a 47KB generation.~~

What actually happened (verified against the plan's commands and every
`TAB_GROUP_CHANGED` event in the 2026-07-2x logs):

- All **9** AMVs in `anime essays` were placed by a **single** plan section,
  `## Consolidate anime/AMV commentary…`. Within its own output the model was
  **9/9 consistent**.
- All **5** AMVs in `music` appear in **no command in the plan** and have **no
  group-change event**. They were already in `music` before the run.
- Same for the astrology example — neither tab was placed by the plan.

So the model was not inconsistent with itself. It was inconsistent with **the
state it was shown**. `build_summary` (`bin/tab-organize:155-161`) puts every
existing group's full membership in the prompt, so those 5 AMVs were visible.
The model read them and invented a competing home anyway — and the prompt's
*"Preserve existing groups that already make sense"* actively discourages
re-filing them.

The only genuine intra-plan divergence found is a single untagged tab
(`𝐁𝐫𝐨 𝐜𝐚𝐫𝐫𝐲𝐢𝐧𝐠 𝐩𝐮𝐫𝐞 𝐯𝐞𝐧𝐠𝐞𝐚𝐧𝐜𝐞 𝐚𝐮𝐫𝐚` → `music`).

**Consequence: a `## Taxonomy` declaration section fixes nothing here.** The
model already declared its policy in a heading and applied it consistently. A
declaration would only have made it commit to "AMV → anime essays" earlier and
file all 14 there — by the 2026-07-28 decision that is *worse*, not better.

### Mode D — silent omission

Tab `2105360957` ("Stationbreak - Announcement Trailer") appears **nowhere in
the plan**, prose or JSON, while its three identical siblings were placed in
`gaming`. It predates the run, so it was in the input. It is still ungrouped.
Corroborated independently: a later `plan` run picked it up as a "stray gaming
tab", which is only possible if the first run dropped it.

Nothing in the pipeline notices a dropped tab. Rate here is low (1 of ~562
placements) but it is unbounded under output truncation — see "Scale ceiling".

### Mode C — plan prose and plan JSON can disagree

Tab `2105360484` is listed under a heading in the plan text but absent from that
section's JSON array. Only the JSON executes, so reviewing the prose does not
tell you what will actually run.

Overall error rate ~1–2% of 552 tabs, concentrated in medium-vs-subject cases.

## Decisions taken

- **AMVs live in `music`.** (User call, 2026-07-28.) The 9 currently in
  `anime essays` should move.

## Scale ceiling (unacknowledged in the original plan)

Measured: 139,243-byte input at 931 tabs (~150 B/tab); 47,605-byte response for
726 tab ids. The response is **35% JSON, 65% prose title echo**. Output scales
at roughly 2× tab count.

If the model hits its output cap, `call_claude` returns the truncated
`result` text, `extract_commands` yields whatever complete fences survived, and
`cmd_execute` runs them and prints "Executing N commands" — with no statement of
what fraction of the input was covered. The styled titles cost ~1 token per
character, so the tabs under discussion are the expensive ones.

Note every proposal in the original plan *added* to the output.

## Proposed changes — `bin/tab-organize`, in priority order

### 1. Existing groups are binding precedent (fixes B)

Prompt rule: *the EXISTING GROUPS block is binding. If a group already contains
tabs of a content type, every new tab of that type goes to that group — do not
create a competing home for it.* Plus explicitly license re-filing existing
members, which the current *"preserve existing groups"* wording discourages.

The capability is already there and unused: the extension merges into a
same-title group via `chrome.tabGroups.query({windowId, title})`
(`browser-tab-tree/extension/background.js:47-67`), and `chrome.tabs.group`
moves an already-grouped tab. Nothing tells the model it may do this.

This addresses the actual failure and generalizes to every content type — no
keyword list required.

### 2. Input-coverage check + persist the input (fixes D, de-risks truncation)

Assert every non-newtab ungrouped tab in the input appears in exactly one
command of the output; print the diff. One set difference.

Requires the input to be re-readable — `cmd_plan` currently discards the summary
it sent, so the exact bytes shown to the model are unrecoverable. Save it as
`plan-<ts>.input.txt` beside the plan. That also fixes the reproducibility
problem noted in the caveats above, and turns silent truncation into a loud
failure.

### 3. Drop the prose title echo (kills C by construction, halves the output)

The per-tab title listing is 65% of the response, exists only for human review,
and is the *sole* source of Mode C. Render titles from `state.json` by id in
`check` / `execute --dry-run` instead — always accurate, zero tokens.

**Open trade-off:** the workflow is `vim <plan>` to edit before executing, and a
plan of bare JSON blocks is harder to edit by hand. Options: keep a minimal
`id — short title` line (cheap, still drifts), or have `check` emit an annotated
copy for review. Needs a decision before implementing.

### 4. Stale-id check, as an error (fixes the dead staleness guard)

`tab-organize check [plan]`: any emitted id absent from `state.json` is an
error, not a warning. 23 `TAB_REPLACED` events in one day make this a live
hazard.

Delete the existing mtime guard at `bin/tab-organize:586` — because `host.py`
rewrites `state.json` on every browser event, it fires for essentially every
plan older than one second, so it is always-on noise that gets ignored.

Also in `check`: prose-vs-JSON id diff (Mode C, if 3 doesn't remove it), and a
per-group diff of what will be added.

### 5. Subject over medium (fixes A)

Prompt rule: *classify by SUBJECT MATTER, not media format — an animated video
about a religious song belongs with religion, not animation.* Cheap, harmless,
likely helps.

## Deferred pending a decision

### `taxonomy.md` — pinned assignments

Optional `browser-sync/taxonomy.md`, one `keyword, keyword -> group` per line,
injected into the prompt as mandatory assignments.

**The design philosophy is sound** — small, optional, pinned exceptions only,
with live group titles as the de-facto vocabulary. That is the answer to "how
does it expand": you add a line when something annoys you twice.

**The matching is not.** Measured on the 931 real titles:

- `"amv" in title.lower()` → **7 of 14** AMVs. NFKC-normalized → all 14. The 7
  missed are the `𝘼𝙈𝙑` styled ones, which include **both titles this plan
  quoted as evidence**. A naive lint would pass clean while missing half the
  misfiled tabs — false confidence on the exact case that triggered the work.
- Short keys are unusable: `ai` → 142 hits, 126 outside `ai/coding`; `art` → 50
  hits, all 50 outside `creative tools` ("Mozart", "Artemis").
- It doesn't generalize: only 6 of 9 tabs in `astrology` contain `astro`. AMV
  has a bracketed lexical tag; almost nothing else does.
- Worse, the file would feed two consumers with **incompatible matching
  semantics** — the model tokenizes `𝘼𝙈𝙑` fine, the lint doesn't. Prompt
  injection would work while verification silently didn't.

If revived: NFKC + casefold, word/bracket boundaries not raw substring, and
prefer URL/channel anchors over title text.

## Dropped

- **`## Taxonomy` declaration section.** Fixes a failure mode that did not
  occur, and would have entrenched the wrong AMV home earlier in generation.
- **Two-pass classify-then-group.** Deferral stands, but not for the original
  reason — it would not fix the observed failure unless its label set is seeded
  from existing group titles *and* it may re-file existing members. Item 1 is
  the real prerequisite; if it works, the rewrite stays unnecessary.

## Separately found — FIXED 2026-07-29

Both done, with a real named pipe under test.

**FIFO half-apply.** The 10s alarm covered both phases, but they fail for
different reasons: `open()` blocks until a reader attaches (a real "extension
not running" signal), while writes block because the reader is draining slowly —
normal at 20KB+ payloads. Now `open_timeout=10` / `write_timeout=120`. On a
stall, `execute` reports how many commands were sent and writes the unsent ones
to `plan-<ts>-remaining.md`.

The remaining-plan half is not a luxury: re-running the original does not work,
because its already-applied `close_tab` commands reference tabs that no longer
exist. Measured on the executed 2026-07-27 plan: **725 validation errors**, so
`execute` refuses outright.

Testing caught a bug in the first version of the fix: a line-buffered
`f.close()` in the `finally` flushes into a pipe nobody is draining and blocks
for ever — hanging in exactly the case the timeout exists to report. Rewritten
on the raw fd, so there is no buffer to flush and the count is exact. Verified:
no reader → 2s, 0 written; slow reader → all 2000 commands / 113KB in 11.3s
(the old code aborted at 10s); stalled reader → honest 151-of-2000 and a
remaining plan that round-trips to exactly 1849 commands.

**Malformed JSON.** `extract_commands` now returns `(commands, skipped)`, and a
skipped block is an error in both `check` and `execute` (`--force` to override),
matching how stale ids are treated. `plan` also flags skipped blocks loudly
rather than printing a success banner over a truncated response.

**Second review pass (2026-07-29)** — five more, all verified and fixed:

- `cmd_resync` still caught `TimeoutError`, which `FifoWriteTimeout` was not, so
  running `resync` with the extension down produced a traceback — in exactly the
  situation resync exists for. `FifoWriteTimeout` now subclasses `TimeoutError`.
- **A complete plan was thrown away when the watchdog fired.** If claude streamed
  the whole plan, emitted its `result` event, then failed to exit, the kill
  discarded a finished plan — a full re-run and double token spend. Now fatal
  only when `final is None`; a kill after the result arrived prints a note and
  keeps the plan. Required a second fix: the `-SIGKILL` return code was itself
  being reported as a claude failure.
- The remaining-plan filename sorted *before* the original (`-` is 0x2D, `.` is
  0x2E), so a bare `execute` after a stall targeted the unrunnable original.
  Fixed with a fresh timestamp.
- `stop_event.set()` ran after `proc.wait()`, so a run finishing just under
  `CLAUDE_TIMEOUT` could have the watchdog wake, flag a false timeout and
  `killpg` an already-reaped pid. Retired the watchdog first.
- A write-phase stall reported "is the browser extension running?" when
  `os.open` had already proved a reader was attached. The exception now carries
  its phase.

Confirmed clean by review: no buffered-close hazard reintroduced; `written` exact
in both directions (a partly-written command always counts as unsent); a
truncated line is dropped by the host's `json.JSONDecodeError` branch and cannot
prefix the next batch, because the host reopens the FIFO per writer-close; the
remaining plan correctly does *not* inherit the sidecar (inheriting it
manufactures false "dropped tab" warnings for tabs that were successfully
closed); all four `execute` outcome combinations archive only on the clean path.

## Original notes on those two

- **`write_all_to_fifo` can leave a plan half-applied** (`bin/tab-organize:389`).
  Measured payload 20,626 B vs a 16KB macOS pipe buffer, so the write already
  blocks on the reader. If the 10s `SIGALRM` fires mid-stream, already-flushed
  commands have executed, and `cmd_execute` catches `TimeoutError`, prints "is
  the browser extension running?" and exits 1 — never reporting what got
  through. Cancel or extend the alarm after the first byte; on timeout report
  the flush count. A stall is plausible: `host.py:flush_outputs` rewrites a
  323KB `state.json` + 121KB `current.md` on *every* event, ~1,800 that run.
- **Malformed JSON is warn-and-continue** (`bin/tab-organize:311`). One bad
  `group_tabs` block silently leaves ~100 tabs unorganized, buried in stderr
  above 179 progress lines. Should abort `execute` or be counted in the summary.
- **Cosmetic:** with the new batched close blocks, the streaming progress
  counter counts `"command"` occurrences, i.e. blocks rather than wire commands,
  so it now under-reports.

## Follow-up action — DONE 2026-07-28

Moved the 9 misplaced AMVs out of `anime essays` into `music` as its own
one-command `group_tabs` plan (`archive/plan-20260728-185904.md`), generated
from live state rather than hand-transcribed since the browser had restarted and
every tab/window id had changed. Verified after: **14/14 AMVs in `music`**, all
in window 2105364792; `anime essays` 75 → 66, `music` 179 → 188.

The split that started this investigation no longer exists, so the binding-
precedent rule now has a correct baseline to preserve.
