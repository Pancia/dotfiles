# Review: roleplay-bookends session/random modes (2026-11-16)

Scope: the uncommitted change to `ai/mods/roleplay-bookends/` (hooks/register.tsx,
types/index.d.ts, tests/modes.test.tsx, tests/flow.test.tsx),
`roleplay/bin/roleplay-roll` (`--roster`), `roleplay/tests/test_roleplay_roll.py`
and `roleplay/docs/claude-roleplay.md`.

Checks run:

- `claude plugin test ai/mods/roleplay-bookends`: 18 pass.
- `claude plugin validate ai/mods/roleplay-bookends`: passes (only the icon warning).
- `cmds test roleplay`: 93 pass.
- Every row of the real `roleplay-roll --roster` (81 rows) round-trips through
  `parseWho`'s regex to the same name and universe, so the random-mode odds
  lookup finds every character.
- Scratch experiments on a copy of the mod (not in the repo): `/clear`
  (`session.end` reason `clear`) in session mode rolls a new character; a second
  `session.start` (hot reload) keeps mode and character; a Reroll between a
  turn's start and its end leaves the opener and closer on the same character;
  with an empty roster, session mode and Reroll fall back to the script;
  `/roleplay session` from random mode (an `update` then a `read` in one
  command dispatch) rolls and names the character.
- Limits of that evidence: the "hot reload" test only called `session.start`
  again, so module variables (`roster`, `rosterLoad`, `turns`) did not reset as
  they do in a real reload. It confirms only that `$.state` keeps the mode and
  character. Findings 6 and 7 (first bullet) come from reading the code, not
  from a run. The mock harness does not model the `session.end` time bound or
  any per-dispatch snapshot of `$.state`.

No high-severity bug found. The findings below are medium and low.

## Findings

### 1. A roster load that times out or fails to start is never retried (medium)

`hooks/register.tsx:279-290` (`loadRoster`). `$.process.run` *rejects* when the
command is still running at `timeoutMs` (5 s here) or cannot start. The catch
branch logs and leaves `rosterLoad` set to the settled promise, with `roster`
still `[]`. Only the empty-output branch (line 284) clears `rosterLoad`. The
comment on line 283 says the opposite intent ("try again at the next need
rather than never").

Scenario: the first roster read lands while the machine is loaded (a slow
`roleplay-roll` start at session start, which is exactly when session mode
calls it). From then until the next mod reload:

- random mode draws no odds on any bookend;
- every Reroll falls back to the script (finding 3: it can return the same
  character and drops the signature note);
- Pick always toasts "The roster did not load".

Fix: set `rosterLoad = null` in the catch branch too (or in a `finally` when
`roster.length === 0`).

### 2. The session character is lost on every resume (medium, design gap)

`register.tsx:28` (`pin` in `$.state`), `:572-579` (`session.end`).
`$.state` lives only for the process. `claude --resume` / `--continue` starts
with `pin = { mode: null, who: null }`, reads the saved default and rolls a new
character. An in-process `/resume` raises `session.end` (reason `resume`). The types say
plainly that no `session.start` follows only for `/clear`; that it is the same
for `/resume` is an inference. Either way, the hook clears `who` and a new
character is rolled. The docs promise
"one character for the whole session", but a resumed session never gets its
character back. Earlier opener rows also vanish on resume (pre-existing).

Fix, if wanted: keep `{ mode, who }` in `$.store` under the session id
(`$.session.id()`, or `e.resume.id` at `session.end`), and read it back in
`session.start` before falling back to the saved default. Prune old ids.

### 3. Fallback roll (roster empty) ignores "never the same" and loses the signature rule (low)

`register.tsx:302-308` (`rollChar`). When `pickChar` returns null, it calls
`ownRoll($, false)`. In that path:

- `not` is ignored, so Reroll can hand back the current character. The toast
  then says "This session: «X»" for the X already in place.
- `sig: ''` is stored, so `whoFor` (`:274`) adds no signature note on any turn.
  The script's tag carried a "spent"/"unlocked" note (in `parseWho`'s `extra`),
  but it is dropped. Characters with a catchphrase then get no "do not use"
  rule for the whole session.

- `ownRoll`'s `process.run` rejects on a timeout. `reroll` (the Reroll button
  and `/roleplay reroll`) and `startSession` (via `/roleplay session`) have no
  catch, so that rejection surfaces as a failed command or press, with no
  toast. Before this change, the script only ran inside `startOpener`'s
  guarded callback.

This path is reached whenever finding 1 fires, and after a roster edit that
leaves every weight 0.

Fix: retry `ownRoll` a few times while `w.name === not`. For the signature,
keep the parsed `extra`, or parse the signature out of it into `sig`. Wrap
`ownRoll` in `rollChar` in a try/catch that returns null, so the existing
"Reroll found no character" toast shows.

### 4. `session.end` rolls a character on every exit, not only on `/clear` (low)

`register.tsx:576-577`. The hook clears `who` and schedules `startSession` for
every reason: `prompt_input_exit`, `logout` and `other` included. In session
mode at a real exit, this can start `roleplay-roll --roster` (and the fallback
roll) while the process shuts down. It does no harm, but it is wasted work
inside the 1.5 s end bound.

Not verified: whether the `$` captured by a `session.end` hook still works after
that bound, in the `/clear` case where the process goes on. If it does not, the
new character is not rolled at `/clear`. `startOpener` then rolls it lazily on
the first prompt, and until then the row says "rolling a character…". The mock
harness does not model the bound, so the scratch `/clear` test passing does not
settle this.

Fix: gate the roll on `e.reason === 'clear' || e.reason === 'resume'`.

### 5. After `/clear`, the mode is not re-read from the saved default (low)

`register.tsx:576` keeps `pin.mode`. `/roleplay reroll` and `/roleplay pick`
switch the session to session mode without saving the default (`setChar`,
`:311`). A session switched that way stays in session mode after `/clear`,
although the saved default says random. The file header comment (`:23-24`) says
the default is "read once per session", and `/clear` starts a new session id.

This is defensible either way. Choose one behaviour and state it in
`roleplay/docs/claude-roleplay.md`. To re-read: set `mode: null` in the
`session.end` update, then call `sessionMode`.

### 6. Reroll can overwrite a Pick made while it was waiting (low)

`register.tsx:315-320`. `reroll` reads `now`, awaits `rollChar` (a process
spawn when the roster is not loaded yet), then `setChar` writes
unconditionally. After a hot reload in session mode, `roster` is `[]` and
nothing reloads it until the first Reroll or Pick. So the first Reroll press
after a reload waits on a process. A Pick chosen in that window is then
replaced by the Reroll result. Two quick Reroll presses produce two toasts, and
the second result wins. Both cases are narrow and cosmetic.

Fix: write with `update($, pin, p => p.who?.name === now?.name ? { ...p, mode: 'session', who: c } : p)`,
and toast only when the write took.

### 7. Pick pane edge cases (low)

`register.tsx:707-733`.

- After a hot reload with the pane open, `roster` (a module variable) is `[]`.
  The pane shows "No character matches" until it is reopened, because the
  render does not load the roster. Fix: in the render, call `loadRoster` when
  `roster` is empty, and write `filter` to force a redraw (or keep the roster
  in a state atom).
- Enter in an empty field picks the first roster row (the first universe's
  first character): `matches(roster, '')` matches everything. An accidental
  Enter changes the character. Fix: ignore Enter on a blank query.
- `/roleplay pick` while the pane is already open resets `filter` to `''`
  (`:328`). The uncontrolled `Input` keeps its text, so the field and the list
  disagree. Fix: pass `value={q}` on open, or skip the reset when the pane is
  already up (`$.ui.panes()`).
- Characters with weight 0 ("off") are listed and pickable. Weighted rolls
  skip them (`pickChar` filters `c > 0`). This is probably intended, but the
  docs do not say so.

### 8. Session-mode signature odds ignore `ROLEPLAY_CATCHPHRASE` (low)

`register.tsx:265-270` (`sigNote`). The 1/3 rate is hard-coded. The script
honours `ROLEPLAY_CATCHPHRASE`, and random mode goes through the script, so the
two modes disagree when the variable is set. The old `hookRoll` path had the
same hard-coded value, so this is not new behaviour. A comment would do.

### 9. Read-after-update relies on `$.state.get` not being a per-dispatch snapshot (low, unverified on the live engine)

`register.tsx:483-489` (`startOpener`), `:587-592` with `:336-338` (the
`/roleplay session` command). Both write `pin` with `update`, then read it
again. The API docs (`index.d.ts:3641`) say "Every `get` of one dispatch reads
one moment, whatever is written meanwhile". If "dispatch" means the whole hook
or callback, the second read returns the old value:

- In `startOpener`, `c` stays `null` and that turn gets no bookend.
- In `/roleplay session` from random mode, `startSession` reads the old
  `mode: 'random'` and returns without rolling. The session then has no
  character until the first prompt rolls one, and the toast names nobody.

Since `update` retries on a version miss, the per-call reading is the likely
one. A scratch test of `/roleplay session` from random mode passes in the mock
harness, so the mock does not snapshot per dispatch. The live engine is
unverified. `update` already resolves to the value it wrote, so the re-reads
are not needed. Pass the mode into `startSession` too:

```ts
if (!c) {
  const rolled = await rollChar($)
  if (rolled) c = (await update($, pin, p => ({ ...p, who: p.who ?? rolled }))).who
}
```

For the command: `startSession($, 'session')` with the mode as a parameter,
and the toast built from what `update` returned.

### 9b. `/roleplay` is not `immediate` (low, UX)

`register.tsx:555-559`. Without `immediate: true`, `/roleplay reroll` or
`/roleplay pick` typed during a turn waits until the turn ends. The Reroll and
Pick buttons act at once. If the command should match the buttons, register it
with `immediate: true`. All four actions only touch display state.

### 10. Test gaps (low)

`tests/modes.test.tsx` does not cover:

- `/clear` (`session.end`) in session mode: a new character, and no roll in
  random mode;
- a hot reload (second `session.start`): mode and character kept;
- a Reroll between a turn's opener and its closer: both on one character
  (holds today, but nothing guards it);
- the roster load failing or throwing: no odds, fallback roll, Reroll's
  `not`, and the retry in finding 1;
- that `/roleplay session|random` saves the default: `store.set` is stubbed
  but never asserted;
- Enter in the Pick field (`onSubmit`), including an empty query;
- a random-mode roll whose character is not in the roster: no odds, links
  still drawn.

`roleplay/tests/test_roleplay_roll.py` does not cover `--roster` fail-open:
a missing or empty roster should print nothing and exit 0. It also does not
cover `--votes --roster`, which must not write the roll log.

`flow.test.tsx` only gained stubs (`command.register`, `store.get`). Without the
`store.get` stub, every existing flow test would fail, so a session that cannot
read the store has no coverage.

## Suspicions that did not hold up

- **Opener and closer of one turn on different characters.** The closer awaits
  the turn's own `roll` promise (`startCloser`, `:520`), and `whoFor` draws the
  signature note once per turn. A Reroll or Pick mid-turn changes only later
  turns. Confirmed by a scratch test.
- **Hot reload losing the mode or character.** `session.start` reads `pin.mode`
  first (`sessionMode`, `:295`), and `startSession` returns when `who` is set.
  The module variables that reset (`roster`, `rosterLoad`) are reloaded lazily.
- **The old random path or the vote links broken.** The random branch is the
  old code plus an odds lookup after the roll. `--votes` is still passed.
  `voteId` still reaches `pendingLine` and `bookend`. Session-mode `Who`s carry
  no `voteId`, so they draw no links and add nothing to `usedVotes`. The odds
  add `cells(s) + 1` to the head width, which matches the drawn `"{s} "`.
- **Odds lookup missing characters.** All 81 real roster rows round-trip
  through `parseWho` to the same name and universe (including multi-word
  universes, ZWJ emoji and quoted traits). The lookup misses only if the roster
  changes after the mod loaded, and then only those characters lose their odds.
- **`--roster` shifting seeded rolls or breaking fail-open.** The branch sits in
  `END`, after the weights are resolved and before any `rand()`, and runs only
  in roster mode. `srand(seed)` in `BEGIN` consumes nothing. An empty roster
  still exits 1 and prints nothing. All-zero weights print rows with 0 odds,
  which `pickChar` turns into the script fallback. No diagnostic reaches stdout.
  The only change in behaviour is that a bare `roster` argument now means
  roster mode instead of hook mode, the same as the bare `list`, `check` and
  `plain` arguments.
- **Session-mode rolls writing the roll log.** The fallback calls the script
  without `--votes`, and the main path does not call it at all. The test asserts
  this.
- **AbovePrompt hiding other plugins' rows.** Each plugin answers only for its
  own row (`AbovePrompt` is asked once per plugin), so returning the session row
  without `next(e)` replaces only this mod's row.
