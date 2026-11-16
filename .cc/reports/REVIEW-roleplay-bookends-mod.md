# Review: roleplay-bookends mod (ai/mods/roleplay-bookends)

Date: 2026-11-15. Scope: `hooks/register.tsx`, `types/index.d.ts`,
`.claude-plugin/plugin.json`, `hooks/hooks.json`, and the
`CLAUDE_CODE_PLUGIN_DIRS` change in `rcs/claude-settings.json`. Checked against
the 2.1.325 mod API (`plugin-authoring/types/claude-code.d.ts`, `reference.md`).
Nothing was run that writes to `rolls.tsv`.

Labels: **CONFIRMED** means traced in the code, the d.ts or the live logs.
**PLAUSIBLE** means the code allows it, but I did not reproduce it.

## Summary

The code on disk does not draw openers. The live checks covered an earlier
version that started the opener at submit time. The current turn.start design
has written nothing since it was saved. The cause is an ordering race between
`prompt.submit` and `turn.start` (finding 1). The other findings are smaller:
state that grows and redraws every row, key collisions, a stale character on
a failed roll, stuck "thinking…" rows, and one change in behaviour once the
roleplay-roll hook is removed.

## 1. The opener never fires for a normal prompt (CONFIRMED, critical)

Where: `prompt.submit` and `turn.start` hooks, `register.tsx:222-247`.

- `prompt.submit` sets `typed` only after `await next(e)`.
- `PromptSubmitResult` in the d.ts says `next(e)` "resolves once the prompt
  entered the session and its turn started, or it was queued behind the
  running one".
- So for a prompt typed while the session is idle, `turn.start` runs while
  `typed` is still `null` (or holds the previous prompt), and it returns early.
- Live evidence: `register.tsx` was saved at 20:05:12 local. `mod-debug.log`
  then shows "submit typed prompt noted" and `turn.complete … who=none` three
  times (20:00, 20:04, 20:08), and no "turn.start … gets an opener" line at
  all (`grep -c turn.start` is 0). `mod-lines.jsonl` has had no row since
  19:57, and no row has the new `"turn"` field. The Claude Code debug logs show
  no skipped or failed hook for the mod, so this is not a throw.

Side effects of the race (CONFIRMED by tracing):

- Only a prompt queued behind a running turn gets an opener, because for it
  `next(e)` resolves at queue time, before its turn starts.
- `typed` stays set to the previous prompt. At the next `turn.start` the check
  `norm(e.text).includes(head)` uses the old prompt's first 60 characters. A
  short old prompt ("ok", "y") is contained in almost any new prompt ("ok now
  fix the tests"). The opener is then written for the old prompt, keyed to the
  old row, and drawn under the old message. The same happens when a prompt is
  repeated word for word.
- With no opener, `openerTurn` is never set, so no closer is drawn either.

Fix:

- In `prompt.submit`, decide and set `typed` before calling `next(e)`. Clear
  it if the result is a drop.
- Add a `dbg` line on each early return in `turn.start`, so the next failure
  shows which guard rejected the turn.

## 2. Short, empty or stale `typed` matches the wrong turn (CONFIRMED, important)

Where: `turn.start`, `register.tsx:233-235`.

- The match is a substring test on the first 60 normalized characters.
  `typed = ""` (an image-only prompt) gives `head = ""`, and every string
  contains `""`. A one-letter prompt matches almost anything.
- A prompt typed mid-turn and folded into that turn raises no `turn.start` of
  its own ("A prompt typed while a turn runs and folded into that turn is no
  run of its own", `reference.md`). Its `typed` stays set until the next
  submit. A task-notification, peer or `/loop` turn that starts before then
  can take it.
- Fix: require an exact normalized match (or a prefix match on `e.text`), and
  skip when `typed` is empty. Clear `typed` on any main-loop `turn.start`
  that does not match, so it never outlives one turn.

## 3. Every row redraws on every write, and the maps never shrink (CONFIRMED, important)

Where: the `openers` and `closers` atoms, `register.tsx:17-18`, and both
`ui.render` hooks.

- Each `UserMessage` and `AssistantMessage` row in the transcript calls
  `read($, openers)` or `read($, closers)`. A `get` while drawing subscribes
  that row ("a later `set` draws it again", d.ts `state`).
- Each turn makes four writes (opener placeholder, opener text, closer
  placeholder, closer text). Each write redraws every subscribed message row,
  and each redraw copies the whole map across the worker boundary. The cost
  grows with rows × turns, so a long session gets slower.
- Nothing is ever deleted. `$.state` survives hot reloads, so the maps keep
  growing across every reload in the session.
- Fix: declare both keys as `StateFamily<Line>` and read and write one member
  per row (`{ plugin, key, id }`, where `id` is a short hash of `keyOf(text)`).
  Then a write redraws only its own row. If you keep one map, cap it at the
  last 50 entries.

## 4. A failed roll draws the previous turn's character (CONFIRMED, important)

Where: `startOpener` returns at `register.tsx:175`; `turn.start` sets
`openerTurn` at `register.tsx:238`.

- `openerTurn` is set before the roll. If the roll finds no character
  (roleplay-roll exits 0 with no output, the roster cannot be read, or
  `parseWho` fails), `startOpener` returns early. A throw has the same effect.
- `who` and `prompt` keep the previous turn's values. At `turn.complete` the
  turn ids match and `who` is set, so a closer is written for the new answer
  with the old character, against the old prompt.
- Fix: set `who = null` at the start of each matched `turn.start`. Better:
  keep per-turn state in a `Map<turnId, {who, prompt}>`, set it only once the
  roll succeeds, and delete the entry at `turn.complete`.

## 5. Module singletons race on queued prompts (PLAUSIBLE, important)

Where: `turn.complete`, `register.tsx:249-262`.

- The hook awaits `next(e)` and a `dbg` process spawn before it reads
  `openerTurn` and `who`. If a prompt is queued, its `turn.start` can run in
  that window. It overwrites `openerTurn`, `who` and `prompt`. Turn A then
  fails the `e.turnId !== openerTurn` test and gets no closer. If the test
  still passes, it gets turn B's character.
- Fix: the per-turn map from finding 4. Read the turn's entry before any
  `await`.

## 6. Turn start waits on process spawns (CONFIRMED that it awaits, PLAUSIBLE that it delays)

Where: `turn.start`, `register.tsx:239-246`.

- Before `next(e)` the hook awaits `dbg` (one spawn), the `tail`/`cat` spawn,
  maybe `roleplay-roll --votes` (bash + awk), a second `dbg`, and an atom
  update. The old submit-time logs show about 50-100 ms for this.
- `HookBudget` stops the 10 s budget clock while a `$` call is in flight, and
  `$.process.run` waits up to 30 s by default. So a stalled spawn could hold
  the turn's first model request for a long time, with no budget to stop it.
- The comment "next(e) may not resolve until later in the turn" does not
  match the d.ts: `turn.start` is "Observe" and `next(e)` resolves to
  `{ turnId }`.
- Fix: in `turn.start`, read `e.turnId` and the text, schedule
  `$.clock.after(0, () => startOpener(...).catch(...))`, and return `next(e)`
  at once. Pass `timeoutMs: 2000` to each `$.process.run`.

## 7. Once the roleplay-roll hook is removed (CONFIRMED)

- The `rolls.tsv` path runs first and still accepts any roll under 15 s old.
  With no hook, the only writers are the mod itself and other sessions. Two
  prompts whose turns start within 15 s reuse the same character and the same
  vote id. The two turns' votes then cannot be told apart in
  `mod-lines.jsonl`. Another session's roll in that window is also adopted.
  Fix: delete the `rolls.tsv` branch when the hook goes, or skip a vote id the
  mod has already used.
- The own-roll path parses the hook-mode JSON output with the `WHO` regex
  directly. Roster quotes come through JSON-escaped, so traits reach Sonnet as
  `\"` (the script notes that Kusanagi's entry has quotes). Fix: `JSON.parse`
  the output and parse `hookSpecificOutput.additionalContext`, or run the
  script in `--plain` mode and add the vote id another way.
- The roster lookup matches the name only and ignores the universe column of
  `rolls.tsv`. A name in two universes would get the first row's emoji and
  traits. `--check` reports duplicate names, so this is low risk.
- The `context` loop in `startOpener` is dead code: it is always called with
  `[]`.
- The main model stops writing its own bookends by itself ("No roll tag → no
  bookends" in the global CLAUDE.md). The roleplay section of that file then
  only costs tokens, and you can trim it.

## 8. Side-by-side: a queued prompt shows a different character (CONFIRMED)

- The settings hook rolls at Enter. A queued prompt's `turn.start` comes when
  the running turn ends, usually more than 15 s later. The mod then rolls its
  own character, which differs from the one the main model got. It also adds
  a second row to `rolls.tsv`.
- This affects testing only and goes away with finding 7's fix.

## 9. A rejected call leaves "thinking…" up (CONFIRMED, minor)

Where: `write`, `register.tsx:104-123`.

- `$.model.complete` rejects when the engine refuses to send the request (a
  model the allowlist blocks, a bad `maxTokens`). The timer's `.catch` only
  logs it, so the placeholder row stays until the next reload.
- A reply that strips to `""` (only quotes or asterisks) sets `text: ""`.
  That is falsy, so the row also draws "thinking…" for good.
- Fix: wrap the call in `try`, and on a rejection or empty text write the
  line with `failed` set.

## 10. Matching by the first 200 characters (CONFIRMED for duplicates, PLAUSIBLE for the rest)

- Duplicate prompts ("continue", "yes") and duplicate replies ("Done.") share
  a key. The newest line replaces the older one under every matching row,
  including old rows. A per-turn key is not available on the render side, so
  a better option is to key by `e.requestId` (the message id) once known.
  Store the line under the text key, then at first draw move it to that row's
  `requestId` and mark the text key as used.
- A paste: `PromptSubmitInput.text` has "pastes already expanded".
  `UserMessage.text` is "the prompt as typed". If the row shows the
  `[Pasted text #1 …]` placeholder, the keys differ, so no opener is drawn and
  the Sonnet call is wasted. Test this with a paste.
- `AssistantMessage` is one text block, and its text omits what the terminal
  hides (`<context>` blocks). `turn.complete`'s `answer` is the turn's final
  visible text. If the final message has two text blocks, or hidden content,
  and the first block is under 200 characters, the keys differ and no closer
  is drawn.
- `UserMessage` rows are not filtered by `e.props.origin.kind`, so a task
  notification row with the same text also gets the opener. This is low risk.
  Add `origin.kind === 'composer'` to the render hook.

## 11. Session lifecycle (CONFIRMED from the d.ts, minor)

- `session.start` never fires on `/clear` or an in-process `/resume`. `who`,
  `prompt`, `lastAnswer` and `typed` carry over. The first opener after a
  clear quotes the cleared conversation's last reply in its prompt. Fix: hook
  `session.end` (it fires on `/clear` and resume) and reset the module state
  there.
- After a resume in a new process, `$.state` is empty, so old rows have no
  bookends. This is expected for display-only state. Log lines are kept in
  `mod-lines.jsonl`.
- `$.session.id()` is read in the timer. A closer that lands after `/clear`
  is logged under the new session id.
- `session.start` does `cat examples.md` outside a `try`. A rejection skips
  the stale-row marking for that load. This is low risk.

## 12. Wrap-width maths (CONFIRMED, cosmetic)

- Without vote links, the head row is one cell wider than `head` counts. The
  separate `<Text> </Text>` after the name and the leading space of
  `<Text> {emoji} </Text>` also draw two spaces between the name and the
  emoji. With vote links the count is exact.
- `cells()` counts ⭐ (U+2B50, East Asian Wide) as 1. It counts 🏴‍☠️ as 4
  because both parts of the ZWJ sequence count. Fullwidth forms (U+FF00-FF60)
  and Hangul count as 1. The 2-cell slack absorbs most of this.
- The timing note `(sonnet opener 1.2s)` has spaces, so it can wrap across two
  rows. `lastIndexOf(meta)` then misses it, and it draws undimmed.
- A single word wider than the row (a path or URL) overflows. Ink then wraps
  it with no bar.
- If the head is wider than the viewport, the head row itself wraps. The body
  is handled correctly (all of it goes below).
- On a terminal without OSC 8, each `Link` draws its text and then the URL in
  dim, so the head row gets four `hammerspoon://` URLs. On remote surfaces a
  non-https link is drawn plain "and said so". Consider drawing the links only
  when `e.surface === 'terminal'`.

## 13. Main-screen redraw (PLAUSIBLE, check once)

- The placeholder-then-fill check ran in one terminal mode. On the main
  (non-fullscreen) screen, rows already printed to scrollback may not redraw,
  so a closer could stay "thinking…" there. Check once with fullscreen off.

## 14. Logging and cost (CONFIRMED, minor)

- `mod-debug.log` gets two or three lines per turn and is never rotated. It
  also adds one process spawn per `dbg` call on the hot paths. Remove the
  debug calls, or gate them on a constant, before the mod goes live.
- `mod-lines.jsonl` and `mod-debug.log` hard-code `$HOME/.local/state`,
  while the `rolls.tsv` read honours `XDG_STATE_HOME`. Use one rule.
- Two Sonnet calls per typed prompt, each sending up to 3,000 characters of
  the prompt and 6,000 of the reply, uncached. That is small but constant.
  `maxTokens: 2000` is far more than a 25-word line needs. 200 would bound a
  runaway reply.

## 15. Benign

- The validate warning "gating hook without .catch: prompt.submit" does no
  harm. The hook never refuses, and a failure after `next(e)` keeps the
  `next` result. A `.catch(($, e, next) => next(e))` silences it. After the
  fix for finding 1 the hook judges before `next`. A failure must still fail
  open there, and the default does that.
- Capturing `$` in a `clock.after` closure is the documented pattern
  ("start it from a hook … keep it going with `$.clock.after`"). A completion
  made from a timer is not tied to the turn's dispatch, so an Esc does not
  abort it.
- `Date` and `Math.random` work in the mod environment. The log timestamps and
  the working `rolls.tsv` age check show this. The local-time parse of
  `rolls.tsv` is off for one hour a year at the DST change. Logging epoch
  seconds would remove that.
- The vote slots (1-4 opener, 5-8 closer; character +, character −, universe
  +, universe −) match `rolevote.lua`.
- `isSummary` blocks are skipped. Subagent and teammate turns are skipped by
  `e.agentId`. Aborted, refused and errored turns get no closer.

## Settings change: `CLAUDE_CODE_PLUGIN_DIRS`

- The `:` separator and the `~` are correct (`reference.md` line 120: paths
  separated by the platform separator, `~` allowed, read from the `env` block
  of `~/.claude/settings.json`).
- The `env` block reaches every Bash call. So every nested `claude` (a
  `claude-p` with `CLAUDE_P_SAFE=0`, SDK hosts without safe mode, the desktop
  app) also loads the mod. Those prompts have origin `sdk`, so the mod does
  nothing there except the awaited `cat examples.md` at startup. The cost is
  small. I did not check whether `--safe-mode` drops plugins named in this
  variable (PLAUSIBLE that it does).
- Every interactive session watches the folder. Any save in
  `ai/mods/roleplay-bookends/`, or a jj checkout or rebase that rewrites it,
  reloads the mod in all live sessions at once. Each reload kills in-flight
  calls and marks their rows "cut off". A broken edit turns bookends off
  everywhere (the hooks fail open, so turns are not blocked).
- The roleplay-roll `UserPromptSubmit` hook is still registered (line 176),
  so both systems run side by side. Remove it only after findings 1, 4 and 7
  are fixed. Until then the mod alone draws no openers.

## Suggested order of fixes

1. Set `typed` before `next(e)`, and add `dbg` on the early returns (finding 1).
   Then check live that "turn.start … gets an opener" appears.
2. Per-turn state keyed by `turnId`; reset `who` per turn (findings 4 and 5).
3. Exact match and clearing `typed` (finding 2).
4. Start the opener from a timer, and return `next(e)` at once (finding 6).
5. `StateFamily` per row, or a cap (finding 3).
6. Before removing the hook: drop the `rolls.tsv` branch and parse JSON (finding 7).
7. Mark rejected and empty calls as failed (finding 9). Remove the debug spawns (finding 14).
