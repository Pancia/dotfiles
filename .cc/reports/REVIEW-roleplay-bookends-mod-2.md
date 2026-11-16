# Review 2: roleplay-bookends mod, live

Date: 2026-11-15 (evening, MST). Scope: `ai/mods/roleplay-bookends/`
(`hooks/register.tsx`, `types/index.d.ts`, `.claude-plugin/plugin.json`),
`bin/rolevotes-review`, `ai/prompts/rolevotes-review.md`,
`lib/lua/seeds/rolevote.lua` and its test, `rcs/claude-settings.json`,
the top of `rcs/claude-user-claude.md`, and `roleplay/docs/claude-roleplay.md`.
Checked against the 2.1.325 mod API (`plugin-authoring/types/claude-code.d.ts`,
`reference.md`). Earlier review: `REVIEW-roleplay-bookends-mod.md`.

Labels: **CONFIRMED** means traced in the code or the d.ts, or reproduced with
the mod's own functions copied into node. **PLAUSIBLE** means the code allows
it, but I did not reproduce it in a live session.

Nothing was run that writes to `~/.local/state/roleplay/`. `roleplay-roll` was
run only with `ROLEPLAY_ROLL_LOG=` (empty), which logs nothing.
`bin/rolevotes-review` was not run.

## Summary

- Nothing blocks or delays a prompt or a turn. `prompt.submit` does no await
  before `next(e)`. `turn.start` returns `next(e)` at once and starts the
  opener on a timer. `turn.complete` schedules its work after `next(e)`. The
  one exception is `session.start`, which awaits a `cat` before the first
  prompt (finding 9).
- The live logs show the mod works: 13 rolls in `rolls.tsv` since 20:45 MST,
  13 "own roll" openers in `mod-debug.log`, and 26 rows in `mod-lines.jsonl`
  (one opener and one closer per vote id, no duplicates). Each roll is logged
  once.
- The main defects are in matching: a stale queue entry can take the next
  turn (finding 1), a paste row can draw another prompt's opener (finding 2),
  and some prompts never show their opener (findings 3 and 4).
- `AbovePrompt` does not hide other plugins' rows (non-finding A).

## 1. A stale queued prompt takes the next turn (CONFIRMED, important)

Where: `turn.start`, `register.tsx:345-358`.

- `prompt.submit` pushes every typed prompt onto `queue`. A prompt typed while
  a turn runs and folded into that turn raises no `turn.start` of its own
  (`reference.md` line 289: "folded into that turn is no run of its own").
  Its entry stays in `queue`.
- `turn.start` takes the **oldest** entry for which
  `text === q || text.includes(q)`. A short stale entry ("y", "ok", "go") is
  a substring of almost any later text.
- Reproduced with the mod's own code. Queue `["y", "yes, now run the tests"]`,
  turn text "yes, now run the tests": the turn picks `"y"`. The real entry
  stays in the queue.
- Effects: Sonnet writes the opener about "y". The opener is keyed under
  `headKey("y")`, so it is drawn under the old folded "y" row (and every
  other "y" row), not under the new prompt. The closer then uses prompt "y".
- A background-task notification turn is the most likely victim. Its text is
  long, so it contains almost any short stale entry. That turn then gets an
  opener and a closer it should not have.
- Old finding 2 asked for an exact match first and for clearing on a miss.
  The empty-text guard is in. The other two parts are not.
- Fix: look for an exact match first, newest first (`findLastIndex`). Use the
  `includes` fallback only for the newest entry, or only for entries of 20
  characters or more. Drop entries older than a few minutes (`q.at` is
  already stored).

## 2. A paste row can draw another prompt's opener (CONFIRMED, important)

Where: `findOpener`, `register.tsx:88-110`.

- For a row that shows a placeholder, a stored prompt matches when it starts
  with the first typed piece, ends with the last piece, and holds the middle
  pieces in order. A piece next to a placeholder at either end is `""`, which
  every prompt starts or ends with.
- Reproduced: turn A is "fix " plus a 20-line paste. Turn B is "fix the
  tests". The row "fix [Pasted text #1 +20 lines]" draws **B's** opener.
  Both match, and `hits[hits.length - 1]` takes the newest.
- The same happens whenever a later prompt starts with the typed text before
  a paste, or ends with the typed text after one ("[paste] what is wrong?").
- Fix: store the prompt's raw line count with the line. Require it to be at
  least the sum of the `+N lines` in the row's placeholders. Among several
  hits, prefer the one with the closest line count, not the newest.
- Old finding 10 also asked for `e.props.origin.kind === 'composer'` on the
  `UserMessage` render. That filter is still missing.

## 3. A prompt with more than 20,000 characters before its last typed text shows no opener (CONFIRMED, minor)

Where: `startOpener`, `register.tsx:289`.

- `full = norm(text).slice(0, 20000)`. For "[big paste] what is wrong?" the
  typed tail is cut off, so `full.endsWith(last)` fails. The row draws no
  opener, but the Sonnet call was still made.
- Reproduced with a 30,000-character paste.
- Fix: store the head and the tail (for example the first 10,000 and the last
  2,000 characters), or store only the typed pieces' fingerprint. See
  finding 5 for why storing less is also faster.

## 4. A prompt of only digits loses its opener once 40 rows exist (CONFIRMED, minor)

Where: `withRow`, `register.tsx:154-161`.

- JavaScript lists integer-like keys ("1", "2", "42") first, whatever the
  insertion order. `withRow` prunes the first keys in that order.
- So once the map holds 40 rows, writing the opener for prompt "2" prunes
  that same row at once. Reproduced: after 40 rows, `'2' in m` is false.
- This user often answers a numbered question with a bare digit.
  `findOpener`'s "newest hit" assumption also breaks for such keys.
- Fix: prefix every key (`'k:' + headKey(text)`), or keep the map as an array
  of `[key, line]` pairs. A `StateFamily` per row (old finding 3) also
  removes this.

## 5. Each opener write copies the whole prompt map into every user row (CONFIRMED cost model, PLAUSIBLE that it is felt)

Where: the `openers` atom and the `UserMessage` render, `register.tsx:399-410`.

- Every `UserMessage` row reads the whole `openers` map, which subscribes it.
  Each turn writes that map twice (placeholder, then text). Each write draws
  every subscribed row again, and each draw copies the map across the worker
  boundary.
- Since the paste fix, each `Line` carries `prompt`, up to 20,000 characters,
  for every prompt, pasted or not.
- Worst case: 40 rows × 20,000 characters = about 800 KB per read. With 100
  user rows in the transcript, one write copies about 80 MB, and one turn
  about 160 MB. With ordinary short prompts the map is about 10-20 KB and the
  cost is small.
- Fix: store `prompt` only for prompts that hold a paste (more than about 800
  characters, or several lines), and store it shortened as in finding 3.
  Better: a `StateFamily<Line>` keyed by a hash of the head key (old
  finding 3), so a write draws only its own row. The paste lookup then needs
  a small separate index atom.

## 6. The reminder row: stale in other sessions, a button with no feedback (CONFIRMED, minor)

Where: `countVotes` and the `AbovePrompt` render, `register.tsx:227-248` and
`378-397`.

- `countVotes` runs only at `session.start` and at each main-loop
  `turn.complete`. When the review session writes `votes-reviewed-at`, every
  other open session keeps its row until its next turn ends.
- The review session itself shows the reminder too, with a Review button that
  opens yet another review tab.
- The Button has no guard. Two presses open two tabs and two Claude sessions.
- The press ignores the result. A nonzero exit (iTerm refuses, `osascript`
  fails) shows nothing. A timeout makes `$.process.run` reject (d.ts
  `ProcessRunInit.timeoutMs`: "killed and the call rejects"), and the
  `void`ed promise has no `.catch`.
- Fix: in `onPress`, `await` the run in a `try`. Show `$.ui.toast` on failure
  or a nonzero exit. Keep a module flag that ignores presses for about
  30 seconds. Optionally run `countVotes` from a `$.clock.every` timer (every
  10 minutes) so all sessions catch up.

Checked and correct: a missing `votes-reviewed-at` counts every vote. An empty
file does the same. A header line or blank lines in `votes.tsv` parse to `NaN`
and are skipped. Local times without a zone parse as local time. DST moves a
vote's age by at most one hour, which does not matter against a one-week
threshold.

One edge: a malformed `votes-reviewed-at` (any text that does not parse)
gives `since = NaN`. `at <= NaN` is false, so every vote counts as waiting,
and the row stays until the file is fixed. The prompt gives the exact `date`
command, so this is PLAUSIBLE only after a hand edit.

## 7. `bin/rolevotes-review` (CONFIRMED for the comment, PLAUSIBLE for the rest)

- No injection: the fish command is a fixed string, passed to `osascript` as
  argv, and the prompt file is read by `cat` inside fish at run time. A `$`
  or a quote in the prompt file cannot break out.
- The comment on line 8 says `claude` is "the usual wrapper". It is not.
  `fish -c 'type -t claude'` prints `file`. The wrapper is
  `my-claude-code-wrapper`, reached through the `cc` abbreviation, and an
  abbreviation does not expand in text that `write text` sends. So the review
  session is not registered with `ccs` and gets no crash tracking. Fix: send
  `my-claude-code-wrapper` instead, or correct the comment.
- `write text` targets `current session of current window`, not the tab the
  script just made. If the focus moves in between, the command goes to the
  wrong session. Fix: `set t to (create tab with default profile)` and
  `tell current session of t`. For the no-window case,
  `set w to (create window with default profile)` and use `w`.
- If iTerm is not running, `tell application "iTerm"` starts it. iTerm can
  open or restore windows of its own while the script counts them, which can
  give an extra window or a "current window is missing value" error.
- The text is typed before fish has started. Anything in fish startup that
  reads the terminal (a `[Y/n]` question) would take it instead.
- `hammerspoon://rolevotes` takes no parameters, so a link from any web page
  can only open review tabs, not run other commands. Each such click starts a
  Claude session, which costs tokens. This is low risk.

## 8. `rolevote.lua` and its test (CONFIRMED)

- The `rolevotes` handler: `err` is `""` when the script wrote nothing to
  stderr, and `""` is true in Lua. So a failure with empty stderr shows the
  alert "rolevotes: " with no reason. Fix:
  `(err ~= "" and err) or ("exit " .. code)`.
- `task` is a local. Hammerspoon can collect an `hs.task` that nothing refers
  to; the completion callback (the failure alert) may then never run
  (PLAUSIBLE). Keep a reference in a module table until the callback runs.
- The test only checks that `rolevotes` is bound. The harness has no
  `hs.task` stub, so the handler body never runs in a test. Add a stub that
  records the path and simulates a start failure and a nonzero exit.
- `test_rolevote_stop_unbinds_both_events` now covers three events. Rename
  it.
- Hammerspoon must be reloaded (Cmd+Ctrl+R) before the link works.

## 9. Smaller items in the mod

- `session.start` awaits `cat examples.md` with no `try`, before the first
  prompt. On a 5-second timeout it rejects. The stale-row marking and the
  first `countVotes` are then skipped, and the first prompt waits up to 5 s.
  Fix: move it into the `clock.after(0, …)` timer, with a `try`. (CONFIRMED.)
- `examples.md` is read only at `session.start`, which fires again on a mod
  reload but not on `/clear`. An edit to `examples.md` reaches a session only
  after a reload or a new session. The docs do not say so. (CONFIRMED.)
- `session.end` resets the module variables but not the `openers` and
  `closers` atoms. After `/clear`, a new prompt with the same text as an old
  one ("continue") draws the old opener until its own placeholder replaces
  it. If its own roll fails, the old one stays. (CONFIRMED, cosmetic.)
- The roll runs in the timer. `turns.set` happens only after `ownRoll`
  finishes (about 50-100 ms, up to 5 s). A turn that ends before then gets no
  closer. Fix: set a per-turn promise in `turn.start` and await it in the
  closer timer. (PLAUSIBLE; normal turns are much longer.)
- If the hooks worker is lost and replaced, `turn.start` can run again in the
  fresh copy (`reference.md` line 261), which rolls and logs a second time.
  (PLAUSIBLE, rare.)
- Remote Control prompts (`origin.kind === 'bridge'`) get no bookends. This
  may be intended; the code comment says "typed prompt" only.
- `maxTokens: 1000`; old finding 14 suggested 200 for a 25-word line.
- `parseWho` handles the whole current roster. I built each of the 81 rows'
  tags with a vote id, both signature variants, through the script's own JSON
  escaping and `JSON.parse`: 0 failures, Malfoid's `"darling"` included. A
  future trait or signature line that holds `]` would end the match early
  and lose the vote id and the note. A tab inside a field would make the JSON
  invalid; `ownRoll` would then return null and draw no opener. Neither
  occurs today. `roleplay-roll --check` could reject both.
- The mod has no tests. `queue` matching, `findOpener`, `withRow`,
  `parseWho` and `countVotes` are pure enough to test with
  `claude plugin test`. Findings 1-4 would each have been one test.

## 10. Headless and nested sessions (CONFIRMED from the types, PLAUSIBLE for safe mode)

- A headless or SDK prompt has `origin.kind === 'sdk'`, so `prompt.submit`
  queues nothing and `turn.start` rolls nothing. No `rolls.tsv` line, no
  Sonnet call.
- What still runs: `session.start` (the awaited `cat`), and one `countVotes`
  spawn at start and after each main-loop turn. `AbovePrompt` is not raised
  headless. The cost is small.
- `claude-p` passes `--safe-mode`, which the dotfiles say disables plugins. I
  did not check that it also drops folders named in
  `CLAUDE_CODE_PLUGIN_DIRS`, and I did not start a nested session to find out.
- The settings `env` block puts `CLAUDE_CODE_PLUGIN_DIRS` into every Bash
  call, so any nested `claude` without safe mode loads all three mods.

## 11. Settings (CONFIRMED)

- The `roleplay-roll` `UserPromptSubmit` hook is gone from the committed
  `rcs/claude-settings.json`, and the live `~/.claude/settings.json` is the
  same file (same inode). The uncommitted changes in it are unrelated
  (`model` moved, `verbose`, `advisorModel`).
- The new hook prints `[now: Sun 2026-11-15 20:28 MST]`. It reaches the model:
  the newest dotfiles transcript holds it 3 times.
- `CLAUDE_CODE_PLUGIN_DIRS` now also names `focus-verbose`. Neither
  `plainify` nor `focus-verbose` hooks `AbovePrompt`, `UserMessage` or
  `AssistantMessage`.

## 12. Docs that no longer match the code (CONFIRMED)

`roleplay/docs/claude-roleplay.md`:

- The go-live note (lines 9-22) is accurate.
- Pieces table, line 28: "format rules only, ~22 lines". The section is now
  8 lines that forbid bookends.
- Pieces table, line 30: the hook is "wired in `rcs/claude-settings.json`".
  It is not.
- Usage, line 244: `--votes` is "what the hook calls here". The mod calls it.
- Vote ids, lines 262-264: "The bookend format in `rcs/claude-user-claude.md`
  turns the id into links". The mod draws the links.
- Vote ids, lines 277-280: votes are "on through the hook command in
  `rcs/claude-settings.json`". They are on through the mod's `ownRoll`.
- "When changes take effect", lines 289-291: the hook-wiring row and the
  CLAUDE.md row no longer apply. Rows are missing for the mod (a save reloads
  it in every open session) and for `examples.md` (read at session start or
  reload only).

Elsewhere:

- `roleplay/bin/roleplay-roll` lines 5 and 21-24: "Runs as a UserPromptSubmit
  hook on EVERY prompt" and "Only the hook should pass [--votes]". In these
  dotfiles the mod is the caller. Fine for a stand-alone `roleplay/`, but say
  so.
- `CLAUDE.md` line 320: "`--votes` (hook only)". The mod passes it.
- `CLAUDE.md` dated reminder (lines 12-15): it says to look for `error` or
  `failed` lines. The debug log never writes the word "failed". A failed
  write logs its reason (`aborted`, `api-error`, `empty reply`,
  `refused: …`), and a failed roll logs `who=none`. A grep for
  `error|failed` misses `aborted`, `empty reply` and `who=none`. Name those
  words in the reminder.
- `docs/claude-global/claude-p.md` line 36: "the fallback rule at the top of
  this file tells a rollless session to omit the bookends". That rule is gone.
- `rcs/claude-user-claude.md` line 309: "`--safe-mode` stops the roleplay
  bookends leaking". With the mod, the main model writes no bookends, so this
  is history now. It is harmless.
- `bin/rolevotes-review` line 8: see finding 7.

`rcs/claude-user-claude.md` lines 1-8 match the code. `ai/prompts/rolevotes-review.md`
matches the `votes.tsv` field order in `rolevote.lua` and the `mod-lines.jsonl`
fields (`voteId`, `kind`). It writes `votes-reviewed-at` only when the user
says the review is done. A session closed before that leaves the reminder up,
and votes cast during the review are marked reviewed without being shown.

## Non-findings, closed

- **A. `AbovePrompt` does not hide other rows.** The band asks each plugin
  for its own row, and `plugin` is a default matcher key: a matcher that
  leaves it out names the hook's own plugin (d.ts `Matcher`).
  `claude plugin validate` reports
  `ui.render{component=AbovePrompt} (default matcher key: plugin)`.
- **B. `$` captured in `onPress`.** This is the documented pattern
  (`reference.md` line 202: `onPress: () => update($, count, …)`), and a press
  runs "in the plugin's own environment".
- **C. `hasSurvey`** is honoured, so the row gives way to a survey.
- **D. Wrap maths.** The head width now counts exactly the five spaces and
  the four 4-cell vote links that are drawn. ⭐ counts 2. A ZWJ flag such as
  🏴‍☠️ still counts 4 instead of 2; the slack absorbs it.

## Old findings: status

| Old | Topic | Status |
|---|---|---|
| 1 | opener never fires | Fixed. `queue` is set before `next(e)`; the live logs show openers |
| 2 | short or stale `typed` | Partial. Empty text skipped; no exact-first match, no clearing (finding 1) |
| 3 | maps grow, every row redraws | Partial. Capped at 40; still one map, now heavier (findings 4, 5) |
| 4 | failed roll reuses the last character | Fixed. `turns` is set only after a successful roll |
| 5 | singletons race on queued prompts | Fixed. Per-turn map, read before any await |
| 6 | turn start waits on spawns | Fixed. Timer, and `timeoutMs` on every run |
| 7 | removing the hook | Fixed. `HOOK_ROLLS = false`, `JSON.parse`, dead loop removed |
| 8 | side-by-side characters differ | Moot. The hook is gone |
| 9 | stuck "thinking…" | Fixed. Rejections and empty replies set `failed` |
| 10 | 200-character keys, pastes, origin | Partial. Paste lookup added with false matches (findings 2, 3); no origin filter |
| 11 | session lifecycle | Mostly fixed. `session.end` resets; atoms not reset; `cat` unguarded (finding 9) |
| 12 | wrap maths | Mostly fixed (non-finding D). Links still drawn on surfaces without OSC 8 |
| 13 | main-screen redraw | Not checked. Settings now use `"tui": "fullscreen"` |
| 14 | debug log, cost | Deferred on purpose. `DEBUG = true` with a dated reminder; `maxTokens` 1000 |

## Suggested order

1. Finding 1: exact match first, newest first, age limit.
2. Findings 2-5 together: prefixed keys, a line count, a shorter stored
   prompt (or `StateFamily`).
3. Finding 6: toast on failure and a press guard.
4. Findings 7 and 8: target the new tab, fix the comment or the command, fix
   the empty-stderr alert, and stub `hs.task` in the test.
5. Finding 12: the doc and reminder edits.
6. Add `claude plugin test` cases for the matching functions.
