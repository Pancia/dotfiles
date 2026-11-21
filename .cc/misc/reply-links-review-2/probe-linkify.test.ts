// Review probes for linkify at c54f7411472c. Each asserts the correct result,
// so a failure is the bug. Copy the mod to a scratch folder, put this file in
// its tests/, and run `claude plugin test <copy>`.
import { expect, test } from 'claude-code/testing'
import { commandToBox, isLoneCommand, linkify } from '../hooks/linkify'
import type { Linked } from '../hooks/linkify'

const CMDS = new Set(['cc:retro', 'clear', 'code-review', 'review', 'config'])
const rows = (l: Linked) =>
  l.segments.flatMap(s => (s.kind === 'commands' ? [`${s.indent}:${s.commands.join(' ')}`] : []))
const kinds = (l: Linked) => l.segments.map(s => s.kind)

test('L1 a glob after a space gets no button', () => {
  expect(rows(linkify('matches **/review and **/clear files', CMDS))).toEqual([])
})

test('L2 an indented code block at the start of a reply gets no button', () => {
  expect(rows(linkify('    /clear', CMDS))).toEqual([])
})

test('L3 an indented code block right after a heading gets no button', () => {
  expect(rows(linkify('## Example\n    /clear', CMDS))).toEqual([])
})

test('L4 an indented code block right after a closed fence gets no button', () => {
  expect(rows(linkify('```\nx\n```\n    /clear', CMDS))).toEqual([])
})

test('L5 code indented inside a list item (6 spaces after "- ") gets no button', () => {
  expect(rows(linkify('- a\n\n      /clear', CMDS))).toEqual([])
})

test('L6 an HTML comment gets no button', () => {
  expect(rows(linkify('<!-- /clear -->', CMDS))).toEqual([])
})

test('L7 a loose list with a fence in an item stays one Markdown element', () => {
  expect(kinds(linkify('1. Run /clear\n\n   ```\n   x\n   ```\n\n2. next', CMDS))).toEqual(['markdown', 'commands'])
})

test('L8 a known name typed alone by the person is taken as a click leftover', () => {
  // By design (isLoneCommand doc): "/compact" typed by hand is replaced by an answer.
  expect(isLoneCommand('/clear', CMDS, [])).toBe(true)
  expect(commandToBox('/clear', '/cc:retro', CMDS, [])).toBe('/cc:retro')
})

test('L9 linkify cost on a long reply (prints ms per call)', () => {
  const para = 'See /Users/anthony/x and run /clear or `/cc:retro`, **Q1 (go)** here.\n'
  const src = Array.from({ length: 400 }, (_, i) => (i % 20 === 19 ? '\n' : para)).join('')
  const t0 = Date.now()
  for (let i = 0; i < 50; i++) linkify(src, CMDS)
  const ms = (Date.now() - t0) / 50
  console.log(`L9 ${src.length} chars: ${ms.toFixed(2)} ms per linkify`)
  expect(ms).toBeLessThan(20)
})
