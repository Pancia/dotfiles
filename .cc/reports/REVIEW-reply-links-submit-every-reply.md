# Review: reply-links fixes and "submit on every reply block"

Commits: d492e1e753aa (fix the command-row review findings), 642f82ae4c90 and
c54f7411472c (every reply block the mod draws ends in `[ submit ↵ ]`; the mod
now draws every non-empty, non-summary block in the fullscreen terminal).
Date: 2026-11-20. Read-only review. The working copy of `ai/mods/reply-links`
is the same as c54f7411472c.

Baseline checks, both from `~/dotfiles`:

- `claude plugin test ai/mods/reply-links`: 81 pass, 0 fail.
- `npx -y -p typescript@5.6.3 tsc -p ai/mods/reply-links`: no errors.

The probes are in `.cc/misc/reply-links-review-2/probe-linkify.test.ts` (L1-L9)
and `.cc/misc/reply-links-review-2/probe-render.test.tsx` (R1, R1b, R2, R2c,
R3-R7, R9, R9b, R9c). They ran in a scratch copy of the mod. Each probe asserts
the correct result, so a failure is the bug. To rerun them, copy the mod to a
`scratch new` folder. Put both files in its `tests/` and run
`claude plugin test <copy>`. I also reran the earlier review's probes
(`.cc/misc/reply-links-review/`) against the current code.

"Confirmed" below means a probe failed in the test kit. The kit runs the mod's
hooks, not the terminal's paint, so anything about what a person sees is
inferred from the tree.

## Plain replies (c54f7411472c)

The person checked a live plain reply and it looks right. I found no problem
on this path that I can show, apart from the small case in finding 5.

Checked:

- **Streaming cost is unchanged.** Before c54 the hook already ran
  `commandsFor` and `linkify` on every block, then returned `next(e)` for a
  plain one. Now it also builds its own tree. `linkify` takes 4-8 ms on a 26 KB
  reply in the kit (probe L9). `countEngine` and `swapEngine` walk only the
  small tree that `next(e)` returns.
- **A `<context>` block does not leak.** The engine types say
  `AssistantMessage.text` already lacks what the terminal hides, a `<context>`
  block included (`types/claude-code/index.d.ts:12647`). The mod draws that text.
- **Plain https links stay the surface's.** A plain reply's Markdown gets
  `pressableLinks: []` (probe R6). The types say a link left out keeps the
  surface's own behaviour.
- **The roleplay closer.** The existing closer tests, with the closer above and
  beneath, pass. The closer keys on `e.props.text`, so a plain block now gets
  the submit row above the closer, as a block with buttons already did.
- **Each block gets its own submit button.** Probe R7: two blocks of one reply
  give two buttons. The c54 commit message says this is intended.

Not checkable in the kit, and not checked: whether the `⏺` column and the
`isFirstOfReply` layout match the engine's own drawing, how wide tables draw,
and any engine-only styling of a plain reply (for example a theme's
`AssistantMessage` rule). The person's live look is the only check of these.

## Earlier findings: are they fixed?

Checked against the new tests in d492e1e753aa and a rerun of the earlier probes
X3-X20 on the current code. X1 and X2 no longer run because `commandToBox`
takes two more arguments now; the new shipped test covers both inputs.

| Earlier finding | Status |
|---|---|
| 1. A draft that starts with "/" is wiped | Fixed. `commandToBox` now needs a lone known name or one of the reply's own commands (`linkify.ts:438-459`). |
| 2. A command click replaces when the read says empty | Fixed. A fill that only adds text is now `append` (`register.tsx:178-180`). |
| 2b. An answer after a command click goes under the command | Fixed only when the block with the answer button also names a slash word. Otherwise not fixed: new finding 1. |
| 3. A command row splits a list item | Fixed. X3, X4 and X16 are now one Markdown element each. Probe L7 (a fence in a loose item) also passes. |
| 4. Text that is not a command gets a button | Partly fixed. X5, X7, X8, X9, X13 and X15 give no row now. X6 (a glob after a space) still does. Indented code with no blank line before it also does: new finding 6. |
| 5. The command row sits between a question and its answers | Fixed: the row comes after the answer row (`linkify.ts:308-309`). |
| 5b. A paragraph's row lands under Where-next | Fixed (X18). X19 and X20 are right too. |
| 6. A failed `command.list` is asked on every draw | Fixed for a list that throws: a 10 s cache, a shared ask and a 1 s wait. The wait has new gaps: findings 2, 3 and 4. |
| 7. Indent not reset after a fence | Fixed (X12). |
| 8. Heading, label, Where-next blank lines | Fixed for a heading (X14) and blank lines (X11). X17 is right. A label's command still makes a row, now by design (the test was renamed). |

## New findings, most severe first

### 1. The answer-replaces-command fix works only when the answering block holds a slash word (confirmed)

`hooks/register.tsx:88-89`, `:124`, `:140`, `:144` and `:172`. `commandsFor`
returns the empty set when `mayHaveCommand` finds no "/" before a letter in this
block. Then `known` is empty. `offered` holds only this block's own commands.
`isLoneCommand` needs one of the two, so it fails.

- Input: block A is `Run /clear.`; click `[ /clear ]`. Block B, in the same
  reply after a tool call or in the next reply, is `**Q1 (go):** Go?` with
  `【Q1: yes | no】`. Click `[ yes ]`.
- Result: the box is `/clear\nQ1 (go): yes` (probe R9b). Enter runs `/clear`
  with the answer as its text. `[ submit ↵ ]` refuses it ("Press Enter to run
  a slash command").
- A command with arguments from another block fails the same way, even when
  block B holds a slash word (`Check /Users/x?`), because `offered` is block B's
  own (probes R9, R9c).
- The shipped test "an answer click replaces a command a click left" passes
  only because its one block holds both the command and the question.
- The command path has the same gap in the other direction. Block A's
  `/code-review high` in the box makes a command click in block B toast
  "Empty the prompt box first".
- No engine fault is needed. A command row and a question in different blocks
  is a normal reply shape.
- Fix: keep, in module state, the last text a command click put in the box,
  and count that text as a lone command too. Or load the command names inside
  `run` when the box starts with "/".

### 2. A `command.list` call that never settles is never asked again, and each later draw waits 1 s (confirmed in the kit)

`hooks/register.tsx:91-104` and `:114-118`. `commandAsk` is cleared only in
`.finally`, so an ask that never settles stays in flight. When the 1 s timer
wins the race, nothing is stored in `commandCache`.

- Input: the first `command.list` call hangs; a second would answer. Draw
  `Run /clear.`, then draw `Then /clear again.`
- Result: `calls=1 waitedAgain=true row=false` (probe R2). The second draw joins
  the hung ask and waits another full second. In that copy of the module no
  reply gets a command row again. Control probe R2c: a reply with no slash,
  mounted the same way, draws at once, so the wait is the ask's.
- On the terminal a new row is blank until its first answer (types, the
  `ui.render` remarks). So each new block with a "/" before a letter is blank
  for 1 s, and any path such as `/Users/...` counts.
- Not checked: whether the real engine rejects a `$` call that outlives its
  hook. The types say a `ui.render` hook's `$` calls "hold it for 30 seconds in
  all, then fail it". If the call then rejects, the gap ends after 30 s.
- Fix: on a timeout, set `commandCache` to `NONE` with the fail TTL, and clear
  `commandAsk` so the next expiry asks again.

### 3. A block drawn while the list was late keeps no command row until something else redraws it (confirmed in the kit)

`hooks/register.tsx:109`. When the 1 s timer wins, the block draws with no row.
The ask fills the cache later, but nothing asks for a new drawing.

- Input: `command.list` answers 1.01 s after the draw of `Run /clear.`
- Result: no row after the answer arrives (probe R1b). A redraw with the same
  props does show it (probe R1), so only the trigger is missing.
- A finished block's text no longer changes. A scroll at the viewport's edge
  (`onScreen`) or a width change redraws it, so the row can come later.
- This hits the first block with a slash in a session, and the first after
  each 60 s expiry, when the list takes over 1 s.
- Fix: when the ask settles after a timeout, call `$.ui.invalidate('ui.render')`.

### 4. A refused `$.clock.after` is not caught, so a slow list stops the drawing (confirmed in the kit)

`hooks/register.tsx:105-113`. The `try`/`catch` expects a refusal to throw. A
refusal does not throw: the engine logs `$.clock.after refused` and `fn` never
runs, as the types say at `clock.after`. The `late` promise then never
resolves, and the draw waits for the ask alone.

- Input: a hook answers `clock.after` with `{ deny }`, and `command.list` never answers.
- Result: the mount does not finish within 4 s (probe R4). In the real engine I
  expect the hook to be skipped after the 30 s `$` budget, with the row blank
  until then.
- With a list that answers, the row still draws (probe R3). A refusal alone does no harm.
- This needs another mod that refuses timers, so it is unlikely. Fix: race the
  ask against `$.clock.sleep(COMMANDS_WAIT_MS)`, whose refusal rejects, and
  treat a rejection as `NONE`.

### 5. A block that a mod beneath empties draws a lone submit button (confirmed, low)

`hooks/register.tsx:123` and `:139`. The empty check reads `e.props.text`, but
the drawing uses the text that a mod beneath passed on (`props.text`).

- Input: a mod beneath rewrites the text to `''`; the block is `Just prose.`
- Result: the tree holds an empty Markdown and `[ submit ↵ ]` (probe R5).
- Fix: also return `inner` when `props.text.trim() === ''`.

### 6. Command buttons still come from code and globs (confirmed, low)

`hooks/linkify.ts:92`, `:241-244` and `:334`. A button needs a name the session
knows, so only a real command name can show up wrongly.

- A glob after a space: `matches **/review and **/clear files` gives
  `/review /clear` (probe L1, earlier X6). The `\*{1,3}` prefix in `CMD_PROSE`
  reads `**` as bold.
- Indented code is skipped only after a blank line, because `:334` needs
  `prevBlank`. CommonMark does not need one at the start of a reply, after a
  heading or after a fence. `    /clear` alone (L2), `## Example\n    /clear`
  (L3) and ```` ```\nx\n```\n    /clear ```` (L4) each give a row.
- Code inside a list item, `- a\n\n      /clear` (six spaces), gives a row
  (L5), because `blockIsList` turns the indented-code check off.
- An HTML comment, `<!-- /clear -->`, gives a row (L6).

### 7. Dead code and a stale comment (seen, low)

- `isPlain` (`hooks/linkify.ts:401-404`) has no caller now.
- `hasButtons` is the constant `true` (`hooks/register.tsx:320`). The comment at
  `:329` still says "One send button at the end of a reply that has buttons".

## Test gaps

- No test with a command row and an answer row in different blocks that share
  one prompt box (finding 1).
- No test of a `command.list` that answers after the 1 s wait (findings 2, 3).
  The "never answers" test checks only the first draw.
- No test of a refused timer (finding 4).
- The "a summary and an empty block" test covers only an empty `e.props.text`,
  not text that a mod beneath empties (finding 5).
