# Review: reply-links command rows (commit b124dfdda18c)

Date: 2026-11-20. Read-only review. The working copy of `ai/mods/reply-links` is
the same as the commit.

Baseline checks:

- `claude plugin test ai/mods/reply-links`: 71 pass, 0 fail.
- `npx -y -p typescript@5.6.3 tsc -p ai/mods/reply-links`: no errors.

Probe tests that show each "confirmed" finding are kept in
`.cc/misc/reply-links-review/probe.test.ts` (linkify) and
`.cc/misc/reply-links-review/probe-render.test.tsx` (render and click). They ran
in a scratch copy of the mod. Each probe asserts the correct result, so a
failure is the bug. The `'?'` probes only print what linkify gives. To rerun
them, copy the mod to a `scratch new` folder, put both files in its `tests/`
(they import `../hooks/linkify`), and run `claude plugin test <copy>`.

Findings, most severe first.

## 1. A draft that starts with "/" is wiped by a command click (confirmed)

`hooks/linkify.ts:386`, `commandToBox`. The test for "only another command" is
`t.startsWith('/') && !t.includes('\n')`. Any one-line draft that starts with a
slash passes it.

- Input: box holds `/Users/anthony/x.log shows an error, why?`, click `[ /cc:retro ]`.
- Result: `commandToBox` returns `/cc:retro`, and `register.tsx:135` replaces
  the box. The draft is lost with no toast. Probe X1.
- Also: a command the person typed with their own arguments,
  `/code-review high focus on auth`, is replaced by `/clear` (probe X2). The
  brief allows that case, but the commit message says "a draft is never touched".
- Fix: replace only when the box holds exactly one of the reply's own command
  texts (or a name in the known set, with no arguments), else toast.

## 2. The command click replaces the box when the read says it is empty (mode confirmed; draft loss inferred)

`hooks/register.tsx:135`. The command path calls `$.prompt.fill({ text })`, which
is mode `replace`. The answer path at `register.tsx:143-147` appends on purpose:
its comment says `prompt.read` answers `''` before the box is mounted, so a draft
the read did not see must not be replaced.

- Input: `prompt.read` answers `''`, click `[ /clear ]`.
- Result: fill is sent with mode `replace` (probe R4 received `["replace"]`). If a
  real draft exists that the read missed, it is wiped.
- Fix: when `box.text === ''`, fill with `mode: 'append'`, as the answer path does.
- The loss rests on the engine behaviour that the comment at `register.tsx:143`
  describes. I did not see it happen.

## 2b. An answer click after a command click puts the answer under the command (confirmed)

`hooks/register.tsx:141` and `hooks/linkify.ts:361` (`addToBox`). `addToBox` does
not know about commands, so it appends the answer on a new line.

- Input: reply `**Q1 (go):** Run /clear?\n【Q1: yes | no】`; click `[ /clear ]`, then `[ yes ]`.
- Result: the box is `/clear\nQ1 (go): yes` (probe R6). Enter would run `/clear`
  with the answer as its text, and `[ submit ↵ ]` refuses it ("Press Enter to run
  a slash command"). The answer cannot be sent as written.
- Fix: an answer or Where-next fill into a box that holds only a command should
  replace the command, or toast.

## 3. A command row splits a list item, so its fence or continuation renders wrong (segments confirmed; rendering inferred)

`hooks/linkify.ts:266` (fence) and `:273-274` (blank line). `commandRow()` calls
`flush()`, so the Markdown is cut into two elements at that point. A list item
that goes on past the cut loses its list context in the second element.

- Input A: `- outer\n  - Run /clear, then:\n    ```sh\n    ls\n    ```\n  - next`.
  The second Markdown element starts with `    ```sh` (probe X4). In CommonMark,
  a fence indented four spaces is an indented code block, so the backticks
  would show as text. `  - next` becomes a new list.
- Input B: `1. Run /clear\n\n    More text of step 1.` The second element is
  `    More text of step 1.` (probe X3), which CommonMark draws as a code block.
  The same text with no command is one element (probe X3b).
- Input C: a loose ordered list, `1. Run /clear\n\n2. Then /review\n\n3. Done`,
  becomes five elements (probe X16). Whether "2." and "3." keep their numbers
  depends on the engine's Markdown. I did not check that.
- This breaks "the reply text must stay as written" for the drawing. Fix: do not
  end a block at a blank line or fence while inside a list item (the next
  non-blank line is indented or is another bullet); emit the row when the list ends.

## 4. Text that is not a command gets a button (confirmed)

`hooks/linkify.ts:90`, `CMD_PROSE`. Names come from `$.command.list()`, which
the engine types say lists built-in, plugin and MCP commands. I did not list it
in a live session, so the names below are assumed: probably `clear`, `config`,
`review`, `init`, and skills such as `run`, `fish` or `cmds`. A common word after
a slash can then match. The probes used the set
`cc:retro, clear, code-review, review, config`.

- File extensions: `edit /config.json and /review.md` gives `[ /config ] [ /review ]`
  (probe X9). The lookahead accepts `.` followed by a letter.
- Globs: `src/**/review and **/clear` gives both (probe X6). `*` is an allowed prefix.
- Text right after a code span: `` see `ai/mods`/clear here `` gives `/clear`
  (probe X5). `^` in `CMD_PROSE` matches the start of each text part, not only of
  the line (`linkify.ts:227` runs it per part).
- A reference link definition, `[doc]: /clear`, matches (probe X7).
- An indented code block (four spaces after a blank line) is read as prose:
  `Example:\n\n    /clear` gives a row at indent 4 (probe X8).
- A fence inside a block quote (`> ```` … `> /clear`) is read as prose (probe X13).
- Fix: require that a `.` or `:` in the lookahead is followed by space or end;
  drop `^` for parts after the first, or check the char before the part; skip
  indented-code and quoted-fence lines.

## 5. The command row sits between a question and its answer buttons (confirmed, by design in the test)

`hooks/linkify.ts:284`. An answer line closes the block before its own row, so
`**Q1 (go):** Run /clear?\n【Q1: yes | no】` draws the question, then `↳ ⌘ [ /clear ]`,
then the answer buttons. The comment at `register.tsx:246` says the answer row is
"right under its question". The test at `tests/linkify.test.ts:148` codifies the
new order, and probe R5 drew it: the command button is key `c1-0` and the
answer buttons are `b2-*`. This is a visible regression to the answer-button
layout whenever a question names a command. Fix: hold the pending row until
after the answer row.

## 5b. A paragraph's row lands under the Where-next list that follows it (confirmed)

`hooks/linkify.ts:273`. The `🧭 **Where next:**` line does not end a block, and
neither does an item. Only a blank line or the `⏳`/`👀` line does.

- Input: `Run /clear.\n🧭 **Where next:**\n- N1 a\n- N2 b\n\n👀 **Needs you:** none`.
- Result: `[ /clear ]` is drawn after item N2, not under "Run /clear." (probe X18).
- A command in a wrapped line of an item also gets its row only after the last
  item, which is right for "under the list" (probe X19).
- Fix: end the block at the Where-next line, as at `⏳`/`👀`.

## 6. A failed `command.list` is asked again on every render (confirmed)

`hooks/register.tsx:84-90`. Only a success is cached. A throw returns `NONE` and
stores nothing.

- Input: `command.list` throws; mount a reply with `run /clear now` three times.
- Result: three calls (probe R1). A reply is drawn many times (streaming, scroll,
  resize), so a broken list is asked for on each draw of each reply that holds a
  slash. Concurrent draws also each start their own call: there is no in-flight
  promise to share.
- Not checked: if `command.list` never settles, the render hook awaits it with no
  time limit, so the reply would not draw. Fix: cache the failure (as `NONE`) for
  the same TTL, share one in-flight promise, and race it against a short timeout.

The cache does not leak between tests: probe R3 gave a new list after R2 cached
another, so each test's mount loads a fresh module. Stale names last at most
60 s, which matches the stated design.

## 7. Block indent is not reset after a fence closes (confirmed, low)

`hooks/linkify.ts:261` and `:277-280`. A fence open emits the row but does not set
`atBlockStart`. Text after the fence keeps the indent of the block before it.

- Input: `  - try /clear\n  ```\n  x\n  ```\nthen /cc:retro`.
- Result: the second row is at indent 2, though `then /cc:retro` is at the margin
  (probe X12).
- The other way: the indent is the first line of the block, so a command in a
  nested bullet gets a row at the list's margin. In probe X4 the command is in
  a bullet at indent 2 and its row is at indent 0.

## 8. Smaller behaviour notes (confirmed)

- A command in a question label still makes a row: `**Q3 (run /clear):** Clear now?`
  gives a `/clear` row (probe X10). The test "a command inside a question label is
  not linked twice" (`tests/linkify.test.ts:192`) checks only the fills, so it
  does not say whether the row is wanted.
- A heading does not end a block: `## Use /clear\nBody /review` puts both under
  the body (probe X14).
- In a Where-next list with blank lines between items, a row goes between the
  items (probe X11). Usual replies have no blank lines there.

## Checked and found correct

- Code-fence contents: no row (existing test, and probe X13 only fails for quoted fences).
- Markdown link targets `[doc](/clear)` and URLs: no match.
- `hasButtons` (`register.tsx:287`): same as before for the old segment kinds; a
  reply with only a command row gets no submit button; a reply with an answer
  row and a command row still gets one (probe R5).
- Segment keys: `cmds${i}`, `lead${i}`, `cell${i}-${j}`, `c${i}-${j}` cannot
  collide with the item (`cell${i}`, `n${i}`) or answer-row (`b${i}-${j}`) keys,
  because `i` is unique per segment.
- `mayHaveCommand` is not quite a superset of what linkify matches. For
  `- N1—/clear` it answers false, but linkify strips the dash and `CMD_PROSE`
  matches at `^` (probe X20). The only effect is a missing button, never a wrong one.

## Test gaps

- No test that a draft starting with `/` survives (finding 1).
- No test of the fill mode on the command path (finding 2).
- No test of a command in a list item followed by a fence or an indented
  continuation (finding 3).
- No false-match tests for extensions, globs, text after a span, or indented code (finding 4).
- No test of a failed or slow `command.list` (finding 6).
- `tests/render.test.tsx:271` checks only that one toast was raised, not its text.
- No render test of a Where-next item that names a command, or of a paragraph
  directly above Where-next (finding 5b).
- No test of a command click followed by an answer click (finding 2b).
