# Review: roleplay vote buttons and roleplay-say odds (2026-11-16)

Scope: the uncommitted change in `ai/mods/roleplay-bookends/` (vote Buttons,
`VOTE_SH`, `castVote`, `myVotes`), `roleplay/bin/roleplay-say` (odds in the
header), its tests and `roleplay/docs/claude-roleplay.md`.

Checked:

- `claude plugin test ai/mods/roleplay-bookends`: 25 pass.
- `cmds test roleplay`: 97 pass.
- `VOTE_SH` extracted from `register.tsx` and run under a throwaway `HOME` in
  the scratchpad: cast, change, clear, a legacy long-form line, and names with
  a tab, a newline, `$(...)`, `%s` and a backslash.
- 30 concurrent runs on different parts, three times, and 5 concurrent up/down
  pairs on one part.
- awk string-versus-number comparison on macOS awk (version 20200816).
- awk `%.0f` against JS `toFixed` rounding.

Not checked: TypeScript types. No `tsc` is installed, and fetching one was
refused. `bun test` does not typecheck.

## Findings

### 1. Concurrent writers lose vote lines (medium impact, rare trigger)

`ai/mods/roleplay-bookends/hooks/register.tsx:438` (the awk-then-`mv` line of `VOTE_SH`)

The script reads `votes.tsv` into a temp file, renames that over the original,
then appends the new line in a separate step. Nothing locks the file. When two
writers overlap, writer B's temp file comes from a snapshot taken before
writer A's append. B's `mv` then deletes A's new line. Possible writers:

- two presses in one session (the types say "two presses before a redraw both land");
- presses in two sessions;
- the Hammerspoon seed, which still handles `r?v=` links in old transcripts and in stand-alone use.

Measured: 30 concurrent presses on 30 different parts kept 21, 30 and 28
lines in three trials. Only lines appended during the overlap are lost. Older
lines are safe, because every snapshot already holds them. At human press
speed the overlap is a few milliseconds, so in practice this is rare. When it
does happen, the loss is silent: both presses show a success toast and draw
bold.

Fix: run the whole script under `/usr/bin/lockf -k -t 5 "$d/votes.lock" sh -c ...`.
Also write the filtered lines and the new line into the temp file before the
`mv`, so one rename makes the whole change (see finding 3). The seed's append
takes no lock. That is acceptable, because the seed now only handles old links.

### 2. Two quick presses on one part can leave two lines and the wrong state (low-medium)

`register.tsx:462-476` (`castVote`)

`castVote` reads `myVotes`, awaits the script, and only then writes `myVotes`.
The `update` callback does not recompute the new vote. It writes the `next`
value that was computed before the await. Two presses inside that window
(about 10-30 ms of process time) both see the old standing vote. The results:

- Same button twice (meant as cast, then clear): both runs cast. The state
  ends "cast" instead of cleared. The file holds one or two identical lines.
- `−` then `+` on one part (a change of mind): both scripts drop, then both
  append. The file can hold both an `up` and a `down` line for one part.
  Reproduced: five concurrent up/down pairs left `ab12 opener up character`
  and `ab12 opener down character` together. The state shows whichever
  `update` ran last.

The reviewer prompt then sees contradictory votes on one part. The next press
on that part repairs the file, because awk drops every matching line.

Fix: serialize presses through a module-level promise chain (losing it on a
hot reload is harmless). Compute `next` inside that chain from a fresh
`read`. The lock from finding 1 then covers other sessions.

### 3. A failed or timed-out run can delete the vote while the state keeps it (low)

`register.tsx:438-442`, `register.tsx:464-468`

The drop (`mv`) is committed before the append runs. If the append fails, or
the 5 s `timeoutMs` kills `sh` between the `mv` and the append, the old line
is gone. `castVote` then shows "Vote not saved" and leaves `myVotes` alone, so
the button still draws the old vote bold. The file holds no vote for that
part. A failed awk also leaves `votes.tsv.tmp.<pid>` behind.

Fix: build the full result in the temp file
(`{ awk '...' "$f"; printf '...new line...'; } > "$f.tmp.$$"`), then `mv` it
once. A failure then changes nothing. Add `trap 'rm -f "$f.tmp.$$"' EXIT`, or
remove the temp file on the failure branch.

### 4. A repeated vote id lets one roll's vote delete another roll's (low)

`register.tsx:438` (`!($2 == id && $3 == p && $5 == k)`)

`roleplay-roll` draws ids at random from 36^4 (about 1.68M) and never checks
for reuse. The roll log already has 314 rows from about two days. The seed's
header says the `rolled` column "tells two rolls apart if an id ever
repeats". The new drop filter ignores that column. A press on a new roll
whose id matches an older voted roll therefore deletes the older roll's vote
on the same place and kind. The `rolled` lookup (newest match) has the same
weakness: a vote on the older of two rolls with one id gets the newer roll's
time. The seed already had that weakness.

A related case: awk compares values that look like numbers as numbers. On
macOS awk, `0x1a` equals `0026`, `1e03` equals `1000`, and `0e00` equals
`0000`. About 0.8% of ids look numeric, so this adds more false matches. It is
negligible on its own.

Fix, best first:

- Make `roleplay-roll` refuse an id that is already in `rolls.tsv`. That removes repeats at the source.
- Or compute `rolled` before the drop, and filter on `$7 == rolled` as well.
- Either way, compare as strings: `$2"" == id""`.

### 5. Changing or clearing a reviewed vote rewrites history (low, design question)

`register.tsx:438-442`

A press drops the old line and appends a line stamped with the current time.
The results:

- Clearing a vote from before `votes-reviewed-at` deletes a record that a review already used.
- Changing such a vote moves it after `votes-reviewed-at`, so it counts as waiting again.

The second is probably wanted. The first loses the record of what was
reviewed. Nothing reads reviewed votes today, so no code breaks. If that
history matters, append a `clear` (or the new vote) and let the reader take
the newest line per part, instead of deleting. Otherwise, say in the doc that
a clear erases the vote.

### 6. roleplay-say's odds can differ from the mod's at exact halves (low, cosmetic)

`roleplay/bin/roleplay-say:150-157`

awk's `sprintf("%.0f")` rounds half to even. JS `toFixed` rounds half up. A
share of exactly 12.5% shows as `12%` in roleplay-say and `13%` in the mod.
Likewise 6.25% shows as `6.2%` against `6.3%`. Today's roster has no such
share: all values are 47ths. Equal weights on 8 universes, or on 16, would
produce one. Fix: add a tiny bias in awk (`sprintf("%.0f", p + 1e-9)`), or
accept it.

### 7. Two identical prompts draw the same vote Buttons (low, older bug, unverified)

`register.tsx:158` (`findOpener` by `headKey`), `register.tsx:979`

Openers are keyed by the prompt's text. Two prompts with the same text (for
example "continue") both draw the newest Line. Both rows then carry identical
`rv-<id>-<n>` keys. The types say a surface "cannot tell apart two that share
[a key]". Each message may be a separate site, but I could not exercise that.
Either way, a vote under the older row records the newer roll. The old links
had the same problem. Fix: key openers by turn as well as text, if that
matters.

### 8. Stale comments after the link removal (low)

- `register.tsx:39-40` and `:45`: "Its button and link open a review session" and "to try the button and link". Only the button remains.
- `register.tsx:11-12`: "records only the vote id and slot". `castVote` records the place and kind, not a slot.
- `lib/lua/seeds/rolevote.lua:120`: calls `hammerspoon://rolevotes` "the review link in the roleplay-bookends mod's reminder row". The mod no longer draws it.
- `bin/rolevotes-review:6-7`: says it is "Called by ... the hammerspoon://rolevotes link".
- `roleplay/bin/roleplay-roll` header (around lines 50-56): still says the seed is the thing that records votes. In this setup the mod now writes them.

### 9. Test gaps (low)

- No test runs `VOTE_SH`. The mock only records argv (`tests/modes.test.tsx`), so the awk, `mv`, `printf` format and quoting have no test. Add a test that runs the real script under a temp `HOME`. Cover cast, change, clear, a name with a tab or newline, a legacy long-form line, and the trailing-tab line format the seed writes.
- No test covers the failure path (non-zero exit: a toast, and the state unchanged).
- No test covers the closer slots 5-8 (`rv-<id>-5` and up, with place `closer`).
- No test covers two presses before a redraw.
- `test_odds_follow_the_mod_format`, `roleplay/tests/test_roleplay_say.py:100-104`: the seed-2 case accepts either character, so it checks only the format. The comment "Seed 1 rolls Someone Else" also depends on the RNG. It holds today.
- No test covers the dim codes on a terminal (`[ -t 1 ]`). That needs a pty, so it is optional.

## Suspicions that did not hold up

- **Quoting and argument handling in `VOTE_SH`.** Values go in as `$1..$5`, never into the script text. `name` passes through `printf '%s'`, then `tr`. A name with `$(date)`, `%s`, a backslash, a tab or a newline was written literally, with the tab and newline turned to spaces. `awk -v` would process backslashes, but `id`, `p` and `k` come from fixed sets: ids are 4 base-36 characters from `roleplay-roll`.
- **The line format.** It matches the seed exactly: 8 fields, the last one empty, so each line ends with a tab and a newline. Long-form lines (`rate`, with an empty id and place) never match the drop filter and survive.
- **A missing `votes.tsv`, or one with no trailing newline.** A missing file skips awk. A file without a final newline gets one from awk's rewrite.
- **`rolls.tsv` path versus `XDG_STATE_HOME`.** `XDG_STATE_HOME` is `~/.local/state` here, so the hard-coded path is right. The seed and `countVotes` hard-code the same path.
- **The width math in `bookend()`.** Each Button draws `[ − ]`: 5 cells, plus one `sp`, and U+2212 counts 1 in `cells()`. So `4 * 6` is right. The rest of the head string matches what is drawn, part for part.
- **Button with a `label` and `Text` children.** `ButtonProps` allows "Children of strings and `Text`", with `label` naming the control. Keys are unique within a bookend, and the opener (1-4) and closer (5-8) cannot collide.
- **The state disagreeing with the file across sessions, reloads or resumes.** Each session's bookends carry their own vote ids, so another session cannot hold a vote for the same part (except for finding 4). `myVotes` is `$.state`, so it survives a hot reload. `openers` and `closers` are also `$.state`. A resume loses them together with `myVotes`, so no bookend can draw a stale vote state. If the state is ever lost while the file keeps a vote, the next press drops the old line before appending, so it cannot leave a duplicate. `myVotes` is never trimmed, unlike the rows (`KEEP`), but each entry is a few bytes.
- **roleplay-say header parsing.** `rest=${header#*» }` then `emoji=${rest%% *}` handles universes with spaces (tested by `OTHER VERSE`). It handles emoji with joiners or variation selectors, which contain no spaces. With an empty emoji, the header keeps two spaces and still matches. `--roster` columns 6 and 7 are the universe's share and the character's share, so `pct($7)` after the name and `pct($6)` after the universe is right. The universe and name strings in `--plain` and `--roster` are the same awk values. No roster entry contains a backslash, so `awk -v` escapes are not a live problem.
- **roleplay-say's fail-loud contract.** The script runs `set -uo pipefail` without `-e`. A failing or early-closed `roleplay-roll --roster` pipe therefore leaves `odds` empty and the line prints without odds. It does not die after the model call, which the comment and `test_odds_are_left_out_when_the_lookup_finds_nothing` both intend.
