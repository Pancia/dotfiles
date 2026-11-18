# Review 2: reply-links mod (answer-line version)

Date: 2026-11-17. Scope: `ai/mods/reply-links/hooks/linkify.ts`, `hooks/register.tsx`,
`tests/*.test.ts(x)`, and the RULE text next to `~/.claude/CLAUDE.md` ("Reply format",
"Questions to me"). The mod was not edited.

Checks run, from `~/dotfiles`:

- `claude plugin validate ai/mods/reply-links`: passes (icon and README warnings only).
- `claude plugin test ai/mods/reply-links`: 23 of 23 pass.
- `npx -y -p typescript@5.6.3 tsc -p ai/mods/reply-links`: no errors.

Repro tests are in `.cc/misc/reply-links-review-2/mod/tests/` (a copy of the mod):
`review2-parse.test.ts` (P*, A*), `review2-render.test.tsx` (G*, E*, F*, C*) and
`review2-toast.test.tsx` (T1, a control that shows the kit sees the mod's toasts). Each test asserts the correct behaviour, so a failing
test confirms a finding. Run: `claude plugin test .cc/misc/reply-links-review-2/mod`.

`.cc/misc/reply-links-review-2/scan.py` counts answer-line shapes in recent replies and prints
counts only. Over the last 48 hours it found 3 answer lines in real replies. All 3 parsed, all
sat under a bulleted one-line question, and each had its own indent. That is too few to say
how the model places lines under block questions or in "Needs you".

## Confirmed (reproduced)

### 1. A second press for the same question adds a contradictory line

- **Where:** `hooks/linkify.ts:174-180` (`addToBox`).
- **Input:** press "yes" on Q4, then "no" on Q4.
- **Result:** the box holds `Q4 (c): yes\nQ4 (c): no`. Changing one's mind is the usual reason
  for a second press, and the person must now edit the box by hand (A1).
- **Fix:** if the box already holds a line that starts with the same `Qn (label): `, replace
  that line instead of appending.

### 2. A label link for one question, then a button for another, share a line

- **Where:** `hooks/linkify.ts:177-179`.
- **Input:** press the `**Q2 (push)**` link (box: `Q2 (push): `), then a Q3 button.
- **Result:** `Q2 (push): Q3 (x): yes`. The "ends in whitespace, so no newline" rule treats the
  label's trailing space as a separator (A2).
- **Fix:** when the box ends with a `Qn (label): ` tail that the new text does not complete,
  drop that dangling tail or start a new line.
- Related, low: `box.endsWith(text)` also skips text that only ends the box by chance:
  `addToBox('please run the tests', 'tests')` adds nothing (A4). Compare whole lines, not a
  suffix. (A bare-ID `Q4: yes` after `Q14: yes` is added correctly, A3.)

### 3. The row under a block question is indented under its last answer bullet

- **Where:** `hooks/linkify.ts:133` (`lastText` / `BULLET`).
- **Input:** the CLAUDE.md block shape at column 0:
  `**Q9 (x)** — I recommend \`E\``, `- **E:** e`, `- **A:** a`, `【Q9: E* | A】`.
- **Result:** indent 2, not 0 (P8). The fallback assumes the last non-blank line is the
  question, but for a block question it is the last answer bullet, so the row reads as part of
  that bullet. The existing tests use this exact shape but never assert its indent.
- **Fix:** remember the indent of the last line that holds a `Qn (` label for the same ID, and
  use it when the answer line has no indent of its own. Related: a numbered question
  (`1. **Q4 (x):** …`) gets indent 0, not 3, because `BULLET` knows only `-` and `*` (P12).

### 4. The rule is added where the user does not read replies as drawn

Only the first item is confirmed; the other two are plausible and are kept here so the gating
reads as one topic.

- **Where:** `hooks/register.tsx:39-45`.
- **`send-user-message` is not skipped (C2, confirmed).** The types say this trait means "the session
  speaks to the person through a message tool". The person then reads the tool's text, which
  this mod never draws, so answer lines would arrive as raw `【Q4: yes* | no】`. Add it to the
  skip list.
- **Main screen (plausible).** Compose gates on `surfaces` holding `terminal`; drawing gates on
  `viewport.isFullscreen`. `PromptComposeInput` has no fullscreen fact, so on the main screen
  (`CLAUDE_CODE_NO_FLICKER=0`, or tmux, which the types say is main-screen by default) the
  model is taught the line but sees raw text. `rcs/claude-settings.json` sets
  `"tui": "fullscreen"`, so this is low risk for this user. A fix could record
  `e.viewport.isFullscreen` on the first `ui.render` and invalidate the prompt section, but the
  cache cost of that change is likely worse than the raw line.
- **Forks (plausible, low).** The types (line ~560) say a `fork` subagent copies the parent's
  prompt, so it carries RULE. It reports to the parent, not the person, so at worst its report
  holds answer lines the parent reads. Its prefix is cached, so the cost is small. There is no
  compose trait that names a subagent, so the mod cannot skip them. For other subagents the
  types point both ways: `$.prompt.compose` is "the call the engine makes for every prompt it
  sends" (types ~3513); an agent definition's `prompt` "replaces the session's" (~744); and the
  `teammate` trait ("an in-process teammate's render of its lead's prompt") shows compose does
  run for loops other than main. So a general-purpose subagent may get RULE too. Not tested
  against a live session; the mod has no way to tell, and the cost is a cached ~180 tokens.
- Placement for caching is right: a static `session` section appended last.

### 5. Answer lines the model may plausibly write are left as raw text, or are mangled

All in `hooks/linkify.ts:42` (`ANSWER_LINE`) and `71-81` (`parseAnswers`).

| Input | Result | Test |
|---|---|---|
| `【Q4：yes* \| no】` (full-width colon, natural next to 【】) | no row; raw line shown | P1 |
| `【Q4: yes* ｜ no】` (full-width bar) | one button labelled `yes* ｜ no` | P2 |
| `  - 【Q4: yes \| no】` (written as a bullet under a bulleted question) | no row; raw | P5 |
| `【Q4: **yes** \| no】` | primary button labelled `**yes*`, fill `…: **yes*` | P3 |
| `【Q4: *yes \| no】` | button labelled `*yes` | P4 |
| `【Q4: * 】` or all answers empty | raw line shown | P11 |
| `` 【Q1: `` \| no】 `` | a Button with an empty label that fills `Q1 (a): ` | E1 |

Full-width space is fine: JS `\s` includes U+3000. There is no escape for `|`, so an answer
that holds one (`A | B|C`) becomes three buttons; RULE should say answers never contain `|`. Fixes: accept `[:：]` and split on
`/[|｜]/`; allow an optional leading `[-*]\s+`; strip `*` and backticks from both ends
before testing for the trailing star (or test `/\*+$/` and remove all of them); drop answers
whose label is empty after cleaning, and drop the whole line (do not draw it raw) when no
answer is left.

### 6. Label lookup and code

- **Label read from code (P6).** `labels()` (`linkify.ts:61-68`) scans the whole source,
  fences and code spans included, and keeps the first match. `` The form is `Q4 (label)`. ``
  ahead of `**Q4 (commit):**` makes the buttons fill `Q4 (label): yes`. Run the label scan on
  the same fence- and span-stripped text the line loop sees, or prefer a bold `**Qn (…)**`
  match.
- **Nested parentheses (P7).** `**Q4 (turn on (beta)):**` gets no link, and its buttons fill
  the bare `Q4: yes`. `[^()]*` cannot match it. Rare.
- **Double-backtick span (P14).** `` `` `**Q1 (x)**` `` `` is rewritten into a link: the
  `CODE_SPAN` regex pairs runs of different lengths. CommonMark closes a span only on a run of
  the same length: match the closing run by back-reference, for example
  ``/(?<!`)(`+)(?!`).*?(?<!`)\1(?!`)/g`` with `matchAll` (not `split`, which would also
  return the inner group and break the odd/even alternation), or use a small scanner. Checked
  with node on the P9, P14 and a two-span string: each span is matched whole. Likely only
  in replies about the reply format or this mod. The common single-backtick case still holds.
- **Fence closed by an info-string line (P10).** Inside a ```` ``` ```` fence, a line
  ```` ```js ```` closes the mod's fence state, but CommonMark does not let a closing fence
  carry an info string. The rest of the fence is then parsed. Close only when the line is the
  marker plus whitespace. Rare.

### 7. Fill feedback

- **Where:** `hooks/register.tsx:78-80`.
- **Refused fill is silent (F1).** Under a dialog, `$.prompt.fill` answers
  `{ isFilled: false, refusal: 'dialog' }`. The mod ignores it, so a press does nothing visible.
  T1 shows the kit records the mod's own toasts, so the missing toast is real. Suggest
  `$.ui.toast('Close the dialog first')` on `refusal === 'dialog'`.
- **No try/catch on the fill branch (F2, low).** In the kit a throwing `prompt.fill` hook
  rejects the press. The real engine skips a failed hook and still answers, and `prompt.read`
  "never rejects", so this is unlikely. The `open` branch already guards; guard this one the
  same way for symmetry, since a run-time throw can unload the mod in every session.

### 8. `pressableLinks` carries every href on every Markdown part

- **Where:** `hooks/register.tsx:82` and `90`.
- **Input:** a reply with more than 256 links in all (E3: 300 bold Q labels).
- **Result:** in the test kit the surface refuses the tree ("pressableLinks names more than
  256 links"), the kit reports "reply-links's ui.render hook was skipped", and the engine draws
  its own. How the real engine treats a refused tree was not tested; the README says a
  run-time hook failure unloads the mod in every session, so do not assume it is safe. The
  input is unrealistic. Each part only needs its own links: pass each segment its own hrefs,
  which also keeps the 256 limit per part.

### 9. Where-next ends at a wrapped line

- **Where:** `hooks/linkify.ts:140-141`.
- **Input:** `- N1 a long item`, then `  that wraps` (indented, no bullet), then `- N2 second`.
- **Result:** N2 is not a link (P13). Treat an indented line as a continuation, not an end.
  Replies seldom hard-wrap, so this is low.

## Plausible (not reproduced)

- **A fill could wipe the person's draft.** `run` reads the box, then fills with the default
  `replace` mode (F3 shows `mode: 'replace'`). `$.prompt.read` answers `''` "where ... none is
  mounted yet", and a `prompt.read` hook that refuses also yields an empty box (PromptFilled
  docs). Either way a press then replaces a real draft. Replace also rewrites the draft as plain
  text; whether attachment placeholders such as pasted images survive that was not checked.
  Every case `addToBox` handles can be done without replace: `append` for a new line or for
  completing a `Qn (label): ` tail (append just the answer word). Only the "replace an earlier
  answer" fix from finding 1 needs `replace`.
- **Answer lines are raw text everywhere else.** On the desktop or mobile surface, in ctrl+o,
  `ccsave` copies and `/plainify` input, the stored line shows as `【Q4: yes* | no】`. That is the
  accepted cost of keeping the stored reply unchanged; noted so it is a decision, not a surprise.
- **A question in an earlier block of the same reply.** Labels are read from `e.props.text`,
  one block. If a reply asks Q4 before a tool call and writes its answer line after it, the
  fill is the bare `Q4: yes`. The CLAUDE.md format repeats the label with the ID, so this is
  rare.

## RULE next to the CLAUDE.md reply format

1. **Block questions: where is "directly under the question"?** CLAUDE.md's block question is
   a head line followed by answer bullets. RULE does not say whether the answer line goes under
   the head or after the bullets. Both parse, but after the bullets at column 0 hits finding 3.
   Add: "For a question with answer bullets, put the line after the last bullet, at the
   question's indent."
2. **"One line each" for carried-over questions.** CLAUDE.md says a still-open question goes
   under Needs you "one line each". RULE says "Add the line again each time the question is
   listed as still open", which makes it two lines. A model that weighs the user's file higher
   may drop the answer line, or put it on the question's line, where it does not parse. Say in
   RULE (or CLAUDE.md) that the answer line does not count as a second line.
3. **Questions with no ID.** RULE says "Use the question's own ID" but not "only when the
   question has one". CLAUDE.md's "accept all, or name the ones to change" for more than three
   decisions has no ID of its own; the model may invent one. Add "Only for a question with an
   ID."
4. **Bullets.** "On a line of its own" does not forbid a bullet marker, and inside a Needs-you
   list a bullet is the natural form (finding 5, P5). Either accept it in the parser or say
   "not as a bullet".
5. **"Never use 【 or 】 for anything else."** A reply that explains this mod needs them. Code
   spans and fences are already left alone, so "outside code" would be accurate.
6. **Word limits.** CLAUDE.md says Needs-you lines do not count toward the word limits. It says
   nothing about answer lines. Minor; the lines are short.
7. Agreements: "Put * after the answer you recommend. Leave it out when you recommend none"
   matches "Give your recommendation if you have one. Do not invent one". The fill
   `Q4 (label): answer` matches the ID-and-label rule. The example uses ASCII `:` and `|`,
   but nothing says full-width forms are wrong (finding 5).

## Checked, not a bug

- An answer line before its question gets the right label, because labels are read from the
  whole block (P15).
- Two answer lines for one ID (the question in the body and again under Needs you) give two
  rows, each working (P16).
- An answer line whose ID has no label in the reply fills the bare ID, `Q3: keep` (existing
  test).
- A tab inside an answer draws (E2).
- The main screen and the desktop surface fall back to the engine (G1, G2). Teammate and bare
  sessions get no rule (C1).
- The stored reply and `e` are never changed; the hook only returns a tree.

## Fixes from the first review: do they hold?

- **Engine-node swap:** holds. The three composition tests (wrapper above, wrapper beneath,
  pass-through beneath) pass, and presses on both mods' buttons work. Roleplay-bookends'
  `AssistantMessage` hook (`roleplay-bookends/hooks/register.tsx:1169-1181`) wraps `inner` the
  same way the test's closer does.
- **Code spans:** hold for single backticks; fails for a double-backtick span around a
  backticked label (P14).
- **Fences:** hold for character and length; an info-string line still closes (P10).
- **Where-next scoping:** holds; a wrapped continuation line ends the list (P13).
- **`addToBox`:** label completion and exact repeat hold; new gaps in findings 1 and 2.
- **Row wrap and open toast** from the first review's plausible list: both done (`flexWrap`,
  toast on a non-zero exit or a throw).

## Missing test coverage

1. The test "a plain reply, a summary and the main screen get no buttons"
   (`tests/render.test.tsx:117-126`) never mounts with `viewport: { isFullscreen: false }`,
   so the main-screen fallback is untested despite the name. G1 shows the kit accepts a
   viewport, and the fallback works.
2. A non-terminal surface (G2 passes).
3. Compose traits `teammate` and `bare` (C1 passes) and `send-user-message` (C2 fails).
4. The `open` failure paths: a non-zero exit and a throw, each with its toast.
5. A refused fill.
6. Row indent under a block question, a numbered question and nested answer bullets.
7. `parseAnswers` with bolded, leading-star, empty and full-width input.
8. `addToBox` with a second answer to the same ID and a label tail of another ID.
9. Label lookup when the same `Qn (…)` appears earlier in code.
10. `isFirstOfReply: false` draws a blank bullet column.
11. A wrapper in the same tier as reply-links (no `tier` given). The composition tests use
    `prepend` and `append`; both real mods load from the same `CLAUDE_CODE_PLUGIN_DIRS` list.
