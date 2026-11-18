# Review: reply-links mod

> Note (2026-11-18): this review covers the first version, which guessed buttons from
> question wording. That parser was replaced by the taught answer line. The repro folder
> `.cc/misc/reply-links-review/` was removed. Its `proto/hooks/register.tsx` fix is now in
> `ai/mods/reply-links/hooks/register.tsx`.

Date: 2026-11-17. Scope: `ai/mods/reply-links/hooks/linkify.ts`, `hooks/register.tsx` and
`tests/*.test.ts(x)`. The mod was not edited.

Checks run:

- `claude plugin validate ai/mods/reply-links`: passes, with only the README, licence and
  icon warnings.
- `claude plugin test ai/mods/reply-links`: 11 of 11 tests pass.
- `tsc` 5.6.3 on a copy, with the engine's generated types: no errors.

Extra tests were run against a copy, `.cc/misc/reply-links-review/mod/tests/`:

- `review.test.ts` holds 14 parser repros. Each test states the correct result, so a failing
  test confirms a bug. 13 of the 14 fail.
- `review-render.test.tsx` and `review-reject.test.tsx` probe drawing and presses.
- `compose.test.tsx`, `compose2.test.tsx` and `order.test.tsx` test how the mod works with
  other plugins in the chain, using inline test plugins. `compose2` presses the buttons of
  both plugins.
- `../scan.ts`, `../scan2.ts`, `../scan3.ts` and `../ctx.ts` run `linkify` over real replies
  (with Bun).
- `../proto/` is a copy with the fix for finding 2. It passes every composition case,
  including the presses.

The parser was run over 227 real assistant text blocks that contain "Needs you" or "Where
next". They came from the 120 newest main-thread transcripts in
`~/.claude/projects/-Users-anthony-dotfiles/`. Of these, 189 replies got at least one button
row, 291 rows in all. The sample is not kept in `.cc/`, because it holds transcript text.
The examples below are made up, but they have the same shape as the real replies.

## Confirmed bugs (reproduced)

### 1. A bulleted one-line question after a block question becomes an answer button of that block

- **Where:** `hooks/linkify.ts:105-110`, with `ANSWER_BULLET` at line 37.
- **Input:** a block question, then a bulleted one-line question. A blank line between the
  two does not help, because blank lines do not close a block.
  ```
  - **Q7 (theme)** — I recommend `yes`
    - **yes:** sets it.
    - **no:** nothing changes.
  - **Q8 (push):** Push to master?
  ```
- **What goes wrong:** the answer-bullet test runs before the question-head tests.
  `- **Q8 (push):**` matches `ANSWER_BULLET`, because the label has no `*` or `:` and is
  40 characters or fewer. So:
  - Q7's row gets a third button, "Q8 (push)". A press on it fills `Q7 (theme): Q8 (push)`.
  - Q8 gets no yes or no buttons.
  - Q8's label gets no link, because the `continue` skips the `Q_BOLD` rewrite.
  - Q7's row moves down, under every question it swallowed.
- **Real replies:** the sample has 10 swallowed questions, 8 of them different. In one reply,
  a block took the four questions after it, so its row had six buttons. This is the usual
  "Needs you" layout: a block question, then the open questions carried over from earlier,
  one line each.
- **Repro:** `review.test.ts` R1 and R1b.
- **Fix:** run the `Q_BLOCK_HEAD` and `Q_ONE_LINE` tests before the answer-bullet test, and
  close the block when either matches. Or make `ANSWER_BULLET` refuse a label that matches
  `^Q\d+ \(`.

### 2. The fallback fires when any hooks-module plugin is beneath, even a pass-through

- **Where:** `hooks/register.tsx:33-43`.
- **Cause:** the check treats any non-engine trace entry with outcome `returned` as "drew its
  own tree". The types say a hook in a hooks module never reads `passed`: "a hooks module's
  hook answers with a copy of its own, so it reads `returned`" (TraceOutcome).
- **Proof:**
  - A plugin beneath that only does `return next(e)` reads `returned`, and reply-links then
    draws no buttons (`compose.test.tsx`).
  - The same happens when a roleplay-style hook beneath returns `inner` unchanged, or wraps it
    with a closer row (`compose.test.tsx`, `compose2.test.tsx`).
  - The fallback logs one line per load, to the debug log only, so the failure is silent.
- **Effect on roleplay-bookends:** its `AssistantMessage` hook calls `next(e)` on every block.
  - **Beneath reply-links:** reply-links never draws, on any reply.
  - **Above reply-links:** the two work together. `compose2.test.tsx` presses an answer
    button, a label link and a vote Button in the closer, and all three work. Roleplay finds
    its closer by `tailKey(e.props.text)`, and that still matches, because reply-links does
    not change `e`.
- **Chain order:** the order of two mods in the same tier is not tied to anything the docs
  promise.
  - The `engine.create` docs say its module list is "in list order, first outermost". They do
    not say that this list follows `CLAUDE_CODE_PLUGIN_DIRS`.
  - The test kit uses load order, first outermost: the plugin under test, then the inline
    plugins in list order (`order.test.tsx`).
  - If a session follows the same rule, the current `CLAUDE_CODE_PLUGIN_DIRS` puts
    roleplay-bookends above reply-links, and it works today.
  - These changes would each turn reply-links off with no warning: a new mod listed after
    reply-links that hooks `AssistantMessage`, a change to the list order, or a built-in
    plugin on `AssistantMessage`.
  - Plausible risk: the same docs say a reload rebuilds "this plugin alone". If a hot reload
    of roleplay-bookends puts it in a new place in the chain, a save could turn reply-links
    off for the rest of the session. This was not tested.
- **Fix:** stop using the trace. Read the tree that `next(e)` returns instead. It holds the
  engine's own drawing as a `{ type: 'engine', ref }` node.
  - If `inner` holds exactly one such node, return `inner` with that node replaced by the
    mod's tree. A wrapper's additions, such as the bookend closer, stay.
  - If it holds none, a plugin beneath drew its own tree, so return `inner`.
  - `.cc/misc/reply-links-review/proto/hooks/register.tsx` does this.
  - With it, five composition cases draw the buttons: pass-through beneath, unchanged beneath,
    closer beneath, closer above and same tier. Each closer that was added is still drawn.
  - Presses on the reply-links buttons and on the closer's Button work with the closer above
    and beneath. The original 11 tests still pass.

### 3. Either/or questions and open questions with a `?` get yes and no buttons

- **Where:** `hooks/linkify.ts:129-134`.
- **Input:** `- **Q3 (layout):** A or B? I recommend A.` or
  `- **Q4 (keep time):** How long should logs stay? I recommend 7 days.`
- **What goes wrong:** any `?` gives yes and no buttons.
  - In the sample, about 22 different lines are choice or open questions and got yes and no.
    Examples are "A, B or C?", "Which of 1–5…?", "How do you switch modes?", "Accept all, or
    name the ones to change?" and "Did you mean X or Y?".
  - Their recommendation ("A", "7", "C") never matches, so neither button is primary.
- **Repro:** R2 and R2b.
- **Fix:** give yes and no only to a yes/no question.
  - Skip the line when the question starts with which, what, how, when or where.
  - Skip it too when it has ` or ` before the `?`.
  - Better: read a choice list ("A, B or C?") and give one button per choice. The
    recommendation is already parsed and can mark the primary button.

### 4. A carried-over yes/no question with no `?` gets no buttons

- **Where:** `hooks/linkify.ts:129-130`.
- **Input:** `- **Q5 (commit):** Still open. A yes commits the work; a no leaves it uncommitted.`
- **What goes wrong:** buttons need a `?` or a bold `**yes**` or `**no**`.
  - The global CLAUDE.md asks that an open question be repeated in later replies, on one line
    that "says what each answer will do". That line is often written like the input above.
  - It names yes and no in plain text and has no `?`, so it gets no row.
  - The sample has about 8 such lines. Examples: "yes doubles…; no keeps…", and "Install it
    when it suits you. I recommend yes."
- **Repro:** R12.
- **Fix:** also give yes and no when the text after the label names both `yes` and `no` as
  words, for example `/\byes\b/i` and `/\bno\b/i`, or when it says "I recommend yes" or
  "I recommend no".

### 5. A one-line question on the "Needs you" line gets no buttons

- **Where:** `hooks/linkify.ts:34`. `Q_ONE_LINE` is anchored at the start of the line.
- **Input:** `👀 **Needs you:** **Q1 (commit fix):** Commit the fix?`. The global CLAUDE.md
  allows a decision on the same line ("End with 👀 **Needs you:** and each decision").
- **What goes wrong:** the label gets a link, but there is no yes or no row. The sample has 6
  such lines, 5 of them different. At least 3 are yes/no questions.
- **Repro:** R3.
- **Fix:** let the one-line pattern accept an optional `👀 **Needs you:**` prefix, for example
  `^(\s*(?:[-*]\s+)?(?:👀\s*\*\*Needs you:\*\*\s*)?)`. Give that row indent 0.

### 6. Inline bold answers in a one-line question are ignored

- **Where:** `hooks/linkify.ts:129-134`.
- **Input:** `- **Q1 (cleanup):** Apply it? **yes:** I edit. **pick:** name the steps. **no:** nothing changes.`
- **What goes wrong:** the row is always yes and no, so "pick" gets no button. A line of this
  shape with no `?` gets no row at all. The sample has 11 such lines.
- **Repro:** R4.
- **Fix:** on a one-line question, collect each `**word:**` that follows the label. Use them
  as the answers when there are two or more. Fall back to yes and no only when there are none.

### 7. Any bullet that starts with N and a number becomes a Where-next link

- **Where:** `hooks/linkify.ts:38` and `92-103`.
- **Input:** a bullet under "Needs you", such as `- 💡 N1 and N2 are not committed yet.`
  The sample has 1 such line.
- **What goes wrong:** N1 becomes a link. A press on it fills "and N2 are not committed yet".
- **Repro:** R5.
- **Fix:** treat N items only after a line that holds `**Where next:**`. Stop at the next line
  that is not a bullet and not blank, or at a `⏳` or `👀` line.

### 8. Text inside inline code is rewritten

- **Where:** `hooks/linkify.ts:90` (`HS_LINK`) and `124-126` (`Q_BOLD`).
- **Input:** ``The parser reads `**Q1 (label)**` at a line start.`` or
  ``Write `[[ 📋 copy ]](hammerspoon://copy?text=x)` after it.``
- **What goes wrong:** a code span shows its text as written, so the reader sees
  `**[Q1 (label)](https://reply-links.invalid/0)**`. For the copy link, the reader sees the
  placeholder address, not the real one. That misleads in any reply about the reply format,
  the copy links or this mod.
- **Repro:** R6 and R7.
- **Fix:** split each line on backtick code spans, and run the replaces only on the parts
  outside them.

### 9. A bold Q label at the start of a line opens a block even when it asks nothing

- **Where:** `hooks/linkify.ts:33` and `112-122`.
- **Input:** `**Q1 (commit)** is answered: committed.`, then `- **Files:** 3 changed.` and
  `- **Tests:** pass.`
- **What goes wrong:** the bullets with bold labels become answer buttons "Files" and "Tests"
  under Q1.
- **Real replies:** none of the 36 different non-yes/no button labels in the sample come from
  this. CLAUDE.md writes answered questions without bold, so the risk is low.
- **Repro:** R8.
- **Fix:** open a block only when the next line that is not blank is an answer bullet. Or
  require an em dash, "I recommend" or the end of the line after the label.

### 10. A recommended answer whose label is in backticks is not primary

- **Where:** `hooks/linkify.ts:37` and `68`.
- **Input:** "I recommend `yes`", then the bullet ``- **`yes`:** …``.
- **What goes wrong:** the answer label keeps its backticks, but the recommendation does not,
  so no button is primary. The backticks also show on the button and in the filled text. No
  case is in the sample.
- **Repro:** R9.
- **Fix:** remove the backticks from the answer label.

### 11. A fence line of the other kind ends a fence

- **Where:** `hooks/linkify.ts:40` and `79-84`.
- **Input:** a ```` ``` ```` fence that holds a `~~~` line, or a ```` ```` ```` fence that
  holds ```` ``` ````.
- **What goes wrong:** the fence state flips, so the rest of the fence is parsed as if it were
  outside it. Rare.
- **Repro:** R10.
- **Fix:** keep the opening marker and its length. Close only on the same character, with at
  least the same length.

### 12. A label link, then a button, puts the ID twice

- **Where:** `hooks/register.tsx:53-59`.
- **Situation:** the label link fills `Q2 (push): `, which ends in a space. The next press
  then appends with no separator, so the box holds `Q2 (push): Q2 (push): yes`
  (`review-render.test.tsx` RR2). Two presses of one button also add the text twice.
- **Fix:** when the box ends with `Qn (label): ` and the action starts with the same text,
  replace that end. Or read the box first and skip an exact repeat. This is minor.

## Plausible problems (not reproduced)

- **The button row does not wrap** (`register.tsx:73-92`). The row is `flexDirection="row"`
  with no `flexWrap`. A block with many or long answers on a narrow terminal, or next to a
  docked pane, may be clipped or squeezed. RR5 shows the row's props, but the test kit does
  not show how the terminal draws it. The types accept `flexWrap="wrap"`.
- **A failed `open` gives no feedback** (`register.tsx:49-51`). A denied `process.run` gives
  no error (RJ), and the exit code is never read, so a copy link that fails does nothing. A
  thrown error rejects the press handler. The mod stayed loaded in the test, but the real
  engine was not tested. Suggest a try/catch, and a `$.ui.toast` on an error or a non-zero
  exit.
- **A cut splits the Markdown.** A button row splits one Markdown block in two, so anything
  that crosses the cut is parsed in two parts. A numbered list may restart. A link reference
  defined at the end is lost to the earlier parts. A part that starts with lines indented four
  spaces or more, such as sub-bullets under a one-line question, would draw as a code block.
  R11 shows the cut. How the terminal draws it was not checked.
- **The mod draws its own bullet column** (`register.tsx:96-104`). It draws `⏺` in the
  default color. The column is blank when `isFirstOfReply` is false (RR6). Any styling the
  engine gives its own bullet is lost on each reply that has a question or a link. Compare it
  by eye with a reply that has no links.
- **The `pressableLinks` limit.** The types allow at most 256 entries. A reply with more than
  256 actions is unlikely. Past the limit the tree may be refused, and the engine then draws
  its own.
- **Markdown near the question dialog.** MarkdownProps says "The terminal refuses it by the
  question dialog". If that covers transcript rows while an AskUserQuestion dialog is open,
  the tree is refused and the engine draws its own. That is a safe failure.

## Checked and not a bug

- **Colon outside the bold.** A line such as ``**Q1 (x)**: I recommend `journal`.``, followed
  by answer bullets, opens a block and works. The recommended button is primary. The sample
  has 2 such cases.
- **The stored reply.** It does not change, and neither does what the model reads. The hook
  never passes new props to `next`. It only returns a tree.
- **Placeholder links.** They stay the same across redraws, because they are numbered in parse
  order. Only these placeholders go into `pressableLinks`, so real https links keep the
  terminal's own click behaviour.
- **Fallbacks.** With `isSummary`, on the main screen (`isFullscreen: false`) and on the
  desktop surface, the engine draws the reply itself (RR4).
- **Primary button.** The recommended button gets `variant="primary"` (RR3).

## Missing test coverage

1. **Other plugins in the chain.** Test a pass-through and a wrapper beneath, and a wrapper
   above, and press through each one. This would have caught finding 2. Use
   `test(name, { plugins: [{ name, tier: 'append', register }] }, …)`, as in
   `compose2.test.tsx`.
2. **Several questions in one reply.** Above all, a block followed by bulleted one-line
   questions, which is the real "Needs you" layout (finding 1).
3. **Other question shapes.** Questions that are not yes/no, carried-over lines with no `?`,
   and inline bold answers (findings 3, 4 and 6).
4. **A question on the `👀 **Needs you:**` line** (finding 5).
5. **N items.** Bullets that start with N outside Where next (finding 7).
6. **Inline code.** Q labels and hammerspoon links in code spans (finding 8).
7. **The early returns in `register.tsx:24-29`.** A surface other than the terminal,
   `isSummary`, `isFullscreen: false`, and a plain reply that falls back to the engine.
8. **The append paths.** A box that ends in whitespace (no separator), and a fill after a
   label link (finding 12).
9. **Drawing details.** The primary variant at render time, and the row indent under an
   indented block head. Only the one-line indent is tested now.
10. **Real reply layouts.** A test with a few made-up "Needs you" sections in the real layouts,
    with the expected rows and fills. A change to the reply format in CLAUDE.md would then
    show up as a test failure.
