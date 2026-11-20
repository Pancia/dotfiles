// Repros from the second review (.cc/reports/REVIEW-reply-links-mod-2.md),
// kept as regression tests. Each asserts what the mod should do. Made-up inputs only.
import { expect, test } from 'claude-code/testing'

import { addToBox, linkify, parseAnswers } from '../hooks/linkify'
import type { Linked } from '../hooks/linkify'

const fills = (l: Linked) =>
  [...l.actions.values()].map(a => (a.kind === 'open' ? `open ${a.url}` : a.text))
const rows = (l: Linked) =>
  l.segments.flatMap(s =>
    s.kind === 'buttons' ? [s.answers.map(a => `${a.isPrimary ? '*' : ''}${a.label}=>${a.text}`)] : [],
  )
const indents = (l: Linked) => l.segments.flatMap(s => (s.kind === 'buttons' ? [s.indent] : []))
const markdown = (l: Linked) => l.segments.flatMap(s => (s.kind === 'markdown' ? [s.text] : []))

test('P1 full-width colon after the ID still parses', async () => {
  expect(rows(linkify('**Q4 (commit):** Commit?\n【Q4：yes* | no】'))).toEqual([
    ['*yes=>Q4 (commit): yes', 'no=>Q4 (commit): no'],
  ])
})

test('P2 full-width bar splits answers', async () => {
  expect(rows(linkify('**Q4 (commit):** Commit?\n【Q4: yes* ｜ no】'))).toEqual([
    ['*yes=>Q4 (commit): yes', 'no=>Q4 (commit): no'],
  ])
})

test('P3 a bolded answer is not mangled into "**yes*"', async () => {
  const a = parseAnswers('**yes** | no', 'Q4 (c)')
  expect(a.map(x => x.label)).toEqual(['yes', 'no'])
})

test('P4 a star before the answer is not kept in the label', async () => {
  const a = parseAnswers('*yes | no', 'Q4 (c)')
  expect(a.map(x => x.label)).toEqual(['yes', 'no'])
})

test('P5 an answer line written as its own bullet still parses', async () => {
  expect(rows(linkify('- **Q4 (commit):** Commit?\n  - 【Q4: yes | no】')).length).toBe(1)
})

test('P6 the label is not taken from a code span or fence', async () => {
  const a = linkify('The form is `Q4 (label)`.\n\n**Q4 (commit):** Commit?\n【Q4: yes | no】')
  expect(rows(a)).toEqual([['yes=>Q4 (commit): yes', 'no=>Q4 (commit): no']])
  const b = linkify('```\n**Q4 (example):** x\n```\n**Q4 (commit):** Commit?\n【Q4: yes | no】')
  expect(rows(b)).toEqual([['yes=>Q4 (commit): yes', 'no=>Q4 (commit): no']])
})

test('P7 a label with nested parentheses gets a link and its fill', async () => {
  const l = linkify('**Q4 (turn on (beta)):** Turn it on?\n【Q4: yes | no】')
  expect(fills(l)).toEqual(['Q4 (turn on (beta)): '])
  expect(rows(l)).toEqual([['yes=>Q4 (turn on (beta)): yes', 'no=>Q4 (turn on (beta)): no']])
})

test('P8 a row under a block question sits at the question indent, not its last bullet', async () => {
  const l = linkify('**Q9 (x)** — I recommend `E`\n- **E:** e\n- **A:** a\n【Q9: E* | A】')
  expect(indents(l)).toEqual([0])
})

test('P9 a double-backtick code span is left as written', async () => {
  const src = 'Write `` **Q1 (x):** I recommend `yes` `` there.'
  const l = linkify(src)
  expect(l.actions.size).toBe(0)
  expect(markdown(l)).toEqual([src])
})

test('P10 a fence line with an info string does not close the fence', async () => {
  const src = '```\nx\n```js\n**Q1 (x):** y\n【Q1: yes | no】\n```'
  const l = linkify(src)
  expect(l.actions.size).toBe(0)
  expect(rows(l)).toEqual([])
})

test('P11 an answer line with no answers is not left as raw text', async () => {
  const l = linkify('**Q4 (c):** Ok?\n【Q4: * 】')
  expect(markdown(l).join('\n').includes('【')).toBe(false)
})

test('P12 a numbered question puts its row under the text', async () => {
  expect(indents(linkify('1. **Q4 (x):** Ok?\n【Q4: yes | no】'))).toEqual([3])
})

test('P13 a Where-next item after a wrapped line is still a link', async () => {
  const l = linkify('🧭 **Where next:**\n- N1 a long item\n  that wraps\n- N2 second')
  expect(fills(l)).toEqual(['N1', 'N2'])
})

test('A1 a second answer to one question replaces the first', async () => {
  expect(addToBox('Q4 (c): yes', 'Q4 (c): no')).toBe('Q4 (c): no')
})

test('A2 a label link for Q2, then a button for Q3, starts a new line', async () => {
  expect(addToBox('Q2 (push): ', 'Q3 (x): yes')).toBe('Q2 (push): \nQ3 (x): yes')
})

test('A3 a bare-ID answer is not skipped because another ID ends the same way', async () => {
  expect(addToBox('Q14: yes', 'Q4: yes')).toBe('Q14: yes\nQ4: yes')
})

test('A4 a Where-next text that ends the draft by chance is still added', async () => {
  expect(addToBox('please run the tests', 'tests')).toBe('please run the tests\ntests')
})

test('P14 a double-backtick span that wraps a backticked label is left as written', async () => {
  const src = 'The format is `` `**Q1 (x)**` `` in the docs.'
  const l = linkify(src)
  expect(l.actions.size).toBe(0)
  expect(markdown(l)).toEqual([src])
})

test('P15 an answer line before its question still gets the label', async () => {
  expect(rows(linkify('【Q4: yes | no】\n**Q4 (commit):** Commit?'))).toEqual([['yes=>Q4 (commit): yes', 'no=>Q4 (commit): no']])
})

test('P16 two lines for one ID give two rows (not a bug, documents behaviour)', async () => {
  const l = linkify('**Q4 (c):** Ok?\n【Q4: yes | no】\n\n👀 **Needs you:**\n- **Q4 (c):** Ok?\n  【Q4: yes | no】')
  expect(rows(l).length).toBe(2)
})
