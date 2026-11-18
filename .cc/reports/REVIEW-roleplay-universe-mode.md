# Review: roleplay-bookends universe mode, `--universe` / `--not` (2026-11-17)

Scope: the uncommitted change to `roleplay/bin/roleplay-roll`,
`roleplay/tests/test_roleplay_roll.py`,
`ai/mods/roleplay-bookends/hooks/register.tsx`, `types/index.d.ts`,
`tests/modes.test.tsx`, `roleplay/docs/claude-roleplay.md`, the
`roleplay-roll` row of `CLAUDE.md`, and
`.cc/reports/REPORT-roleplay-who-did-what.md`.

No high-severity bug found. One medium finding (a universe that cannot roll
silently stops all bookends), the rest low.

## Checks run, and their limits

- `cmds test roleplay`: 105 pass.
- `claude plugin test ai/mods/roleplay-bookends`: 39 pass.
- `npx -y -p typescript@5.6.3 tsc -p ai/mods/roleplay-bookends`: clean.
- **Default rolls are byte-for-byte unchanged.** The old script (`jj file show
  -r @- roleplay/bin/roleplay-roll`) and the new one, on a copy of the real
  roster, for `ROLEPLAY_SEED` 0..400 in each of hook (no flag), `--plain`,
  `--list`, `--check` and `--roster`: 0 differences in 2005 runs.
- **`--universe`/`--not` on real data.** For every one of the 81
  `--roster` rows, `--plain --universe=U --not=N` over 6 seeds: never printed
  N, never printed empty, always the right universe. Names with spaces and
  parentheses (`Houshou Marine (Uncut)`, `Artoria Pendragon (Saber)`) go
  through `sh -c '… "$@"' sh …` intact.
- **Fail-open held** on every script probe: unknown universe, universe whose
  members are all weight 0, empty `--universe=`. Each printed nothing (or a
  normal roll for the empty flag) and exited 0.
- **Mod probes** ran in a scratch copy of the mod with extra test files (not
  in the repo). Their roll mock answers like the real script: empty output for
  a universe nobody can roll (the script run above printed `[]` for such a
  universe, and `test_universe_with_no_member_that_can_roll_fails_open`
  pins it). Limit: the mock engine dispatches commands synchronously, so the
  race probe needed the roster forced empty and a hand-placed yield.
- Not run: a real hot reload. Findings on reload and resume are traced from
  the code.

## Findings

### 1. A pinned universe that cannot roll stops every bookend, silently (medium, verified)

`hooks/register.tsx:770-778` (the universe branch of `startOpener`),
`:518-520` (`startSession`'s roster check), `:332-347` (`loadRoster`),
`:1037-1062` (the universe Pick pane).

The universe branch calls `ownRoll($, true, u, …)` and, when it returns null,
writes nothing. There is no fallback. The script returns nothing whenever
`--universe` names a universe it cannot roll in (`roleplay-roll:274-275`). Two
ways to get there:

- **Pick a universe whose members are all weight 0.** `--roster` prints such a
  universe with share 0 and every member at 0, exactly as it prints a benched
  universe (`@universe | X | 0`). The mod cannot tell them apart, so Pick lists
  both as "0% · N characters". A benched universe rolls; the all-off one never
  does. Probe: pin = an all-off universe, two typed prompts. Both rolls were
  `--votes --universe=DEAD`, both returned empty, no opener row, 0 model calls,
  and the pin stayed. It stays for the whole session and is saved, so
  `--resume` brings it back too.
- **Edit the roster mid-session** (rename a universe, or set all its members to
  0). `loadRoster` caches the roster for the module's life and roster.tsv is
  not imported, so no reload happens. `startSession`'s "gone from the roster"
  check reads the stale cache and passes. Probe: after the script began
  failing for the pinned universe, the pin stayed and the next prompt got no
  bookend (1 model call for 2 prompts).

This also falsifies the doc line "A pinned universe that is no longer in the
roster is replaced at the next prompt" (`roleplay/docs/claude-roleplay.md`):
true only when the mod has re-read the roster (new session, reload).

Fix: in the universe branch, when `ownRoll` returns null: set
`rosterLoad = null`, re-run the `startSession` check (so a gone universe is
replaced), and fall back to an unrestricted `ownRoll($)` for this turn, with a
`dbg` line. In Pick, hide or mark universes with no member that can roll. That
needs `--roster` to expose the within-universe share. Note that `parseRoster`
drops any row whose field count is not exactly 7 (`register.tsx:103`), so a new
8th column must change that check to `< 7` in the same commit, or every row is
dropped.

### 2. A Reroll in flight can put the session back in universe mode after a switch away (low, verified with a forced window)

`hooks/register.tsx:452`. The guard `(x.universe ?? null) === was` checks only
the universe. A mode switch to session (or random) keeps `universe`, so the
guard still passes and the write sets `mode: 'universe'` again. Probe (roster
forced empty, so Reroll goes through the script fallback): `/roleplay reroll`
then `/roleplay session` at once. Result: saved default `session`, the toast
"Session mode: «Togusa» …", but the pin was `mode: 'universe'`. The row and the
bookends then follow universe mode while the user was told session mode.

With the roster loaded the window is a few microtasks, so in practice it
needs a roster that failed to load (up to 5 s per script run, up to 4 runs).
The session-mode Reroll at `:465` has the same shape (it predates this change),
and now also races a switch into universe mode.

Fix: add `x.mode === p0.mode` to both guards.

### 3. Pick of the current universe drops the no-repeat memory (low, verified)

`hooks/register.tsx:429-433` (`setUniverse`). It sets `lastInUniverse = ''`
even when the picked universe is the one already pinned. Probe: a prompt rolled
Togusa, Pick chose the same universe, and the next roll had no `--not=`. The
same memory is also lost on every mod reload (module state), so the docs'
"never the same one twice in a row" has exceptions.

Fix: reset only when the universe changes:
`if (p.universe !== u) lastInUniverse = ''`. Optionally soften the doc to
"rarely the same one twice in a row" or name the reload exception.

### 4. Odds shown in universe mode are wrong for a benched universe and ignore `--not` (low, verified)

`hooks/register.tsx:778`.

- **Benched universe:** `c.u` is 0, so `c` is forced to 0. Probe: a bookend
  from a benched universe drew `0%` for the character and `0%` for the
  universe, though the character actually rolled. The docs say a benched
  universe "can be picked", so this shows up as soon as one is.
- **`--not`:** the shown share is `cwt / usum`, the chance before the previous
  character is excluded. In a 2-member universe it shows 50% for a roll that
  was certain. In GURREN LAGANN (8 members) it shows 12.5% for about 14.3%.
- Rounding: `c.c / c.u` divides two 6-decimal values. On the real roster the
  error is below what `pct` shows, so this one is not a problem today.

Fix: have the script report the within-universe share (the same `--roster`
column as finding 1), and decide whether the odds should be conditional on
`--not`. At least do not draw `0%` for a universe that rolled.

### 5. `awk -v` mangles a backslash in a name (low, verified, latent)

`roleplay/bin/roleplay-roll:313`. `awk -v only_u="$only_u" -v not_c="$not_c"`
processes escape sequences in the value. A roster universe `X\\Y` passed as
`--universe=X\\Y` printed nothing: awk turned `\\` into `\` and the name
did not match. The real roster has no backslashes, so nothing breaks today.

Fix: pass both through the environment and read `ENVIRON["RP_ONLY_U"]` in the
awk program, which takes the bytes as they are.

### 6. Session-to-universe carry-over is reachable only by typing the command (low, verified by reading)

`hooks/register.tsx:479` and `:983`. The button cycles random → universe →
session → random, so from session mode a press goes to random, never to
universe. The carry-over (`was.mode === 'session'`) runs only for a typed
`/roleplay universe`. With the button, random → universe reuses whatever
`universe` the pin last held, which can be from much earlier in the session.
In the same way, universe → session shows a stale `who` from earlier session
mode instead of rolling. That part predates the change (random → session did
it too).

The docs say "Switching from session mode keeps the session character's
universe" without saying it needs the command.

Fix: say so in the docs. Or clear the stale `universe` when leaving universe
mode, so the next entry rolls or carries afresh.

### 7. Racing openers around `lastInUniverse` and `/clear` (low, suspected)

- `hooks/register.tsx:773-774`. `lastInUniverse` is read before the roll's
  process and written after it. Two openers overlap only if a turn ends while
  its opener is still rolling (abort at once, then resubmit). The second roll
  then passes a stale or empty `--not`, so a repeat is possible. A queued
  prompt that folds into a running turn starts no opener, so it does not
  touch this.
- `hooks/register.tsx:871-885` with `:766`. After `/clear`, a prompt typed
  before the session id moves on runs `startSession` under the old id. In
  universe mode the universe is null by then, so it rolls one and `savePin`
  stores it under the old id, overwriting the old session's saved universe.
  The `later()` wait guards only the timer path. Session mode has the same
  hole, from before this change.

Fix (optional): snapshot the session id in `startOpener` and skip `savePin`
while it equals the id that just ended.

### 8. Stale comments (low, verified)

- `register.tsx:130-131`: the `pickChar` comment now sits above `MODES`, not
  above `pickChar` (`:163`).
- `register.tsx:472`: "/roleplay session|random and the row's mode button"
  omits universe.
- `register.tsx:1168` ("random mode only") and `:1227` ("Random mode's odds"):
  universe mode draws them too.
- `roleplay/docs/claude-roleplay.md`, the two-mode paragraph: "`/roleplay
  reroll` and `/roleplay pick` … put the session in session mode" is no longer
  true in universe mode. The new paragraph says so, but the old sentence reads
  as current.

## Clean traces (no finding)

- **Old atom shape after a hot reload** (`{ mode, who }`, no `universe`): every
  read uses `p.universe ?? null` or a truthiness test. `restorePin`'s early
  return `now.who || now.universe` treats a missing key as null. Mode values
  stay valid for `MODES.indexOf`.
- **Pins saved before this change:** `restorePin` (`:390-393`) accepts them
  through `isMode` and fills in `universe: null`. `sessionMode` reads a saved
  `'universe'` default. An old copy of the mod would read `'universe'` as
  random, which fails safe.
- **Resume:** `session.end` (reason `resume`) nulls `who` and `universe`, then
  `later()` waits for the new id and `restorePin` loads its saved pin,
  including `universe`. Correct by trace, but there is no test for it.
- **Concurrent first rolls:** `session.start`'s timer and a quick first prompt
  can both roll a universe. The guard at `:523` keeps the first.
- **Reroll vs Pick, and double Reroll:** the universe guard keeps the Pick, and
  a double press changes the universe once.
- **SYS:** the shipped string equals `.cc/misc/roleplay-who-did-what/new3.txt`
  (whitespace-normalised). The `.cc/misc` inputs are made up and hold no
  private text. The evidence is thin: one character on one real reply, n=8 and
  n=10. It is good enough for a prompt tweak, but not a measured rate.

## Test gaps

Mod (`tests/modes.test.tsx`): the roll mock returns the same Togusa tag
whatever the flags, so these paths have no test:

- a universe roll that returns nothing (finding 1);
- Reroll racing a mode switch (finding 2);
- Pick of the current universe (finding 3);
- the benched-universe odds (finding 4);
- universe mode across `--resume`;
- the button path session → random → universe and its stale universe
  (finding 6).

The fixture also has GHOST IN THE SHELL with one member yet a 14% in-universe
share. The test checks the arithmetic, not a share a real roster could
produce. A refactor that counts members would fail it for the wrong reason.

Script (`roleplay/tests/test_roleplay_roll.py`):

- no test of `--not` when the excluded character's peers have unequal weights;
- no test of `--not` without `--universe` (stage 1 runs as normal, then the
  name is excluded only if it is in the chosen universe);
- no test that an empty `--universe=` gives the normal roll;
- no test of a name that appears in two universes;
- no pinned check that a no-flag seeded roll matches the old script. The
  existing seeded tests cover this in part. The 2005-run comparison above is
  the stronger evidence.
