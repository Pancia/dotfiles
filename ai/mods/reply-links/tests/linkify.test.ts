import { expect, test } from 'claude-code/testing'

import { addToBox, linkify, parseAnswers } from '../hooks/linkify'
import type { Linked } from '../hooks/linkify'

const fills = (l: Linked) =>
  [...l.actions.values()].map(a => (a.kind === 'fill' ? a.text : `open ${a.url}`))

const rows = (l: Linked) =>
  l.segments.flatMap(s =>
    s.kind === 'buttons' ? [s.answers.map(a => `${a.isPrimary ? '*' : ''}${a.text}`)] : [],
  )

const indents = (l: Linked) => l.segments.flatMap(s => (s.kind === 'buttons' ? [s.indent] : []))

const markdown = (l: Linked) =>
  l.segments.flatMap(s => (s.kind === 'markdown' ? [s.text] : []))

test('an answer line becomes a row in its place, with the label from the reply', async () => {
  const l = linkify(
    ['Done.', '', '**Q4 (commit):** Commit these changes?', '【Q4: yes* | no】', '', 'More text.'].join('\n'),
  )
  expect(rows(l)).toEqual([['*Q4 (commit): yes', 'Q4 (commit): no']])
  expect(l.segments.map(s => s.kind)).toEqual(['markdown', 'buttons', 'markdown'])
  expect(markdown(l)[1]).toBe('More text.')
  expect(markdown(l).join('\n').includes('【')).toBe(false)
})

test('a block question gets its answers from the line, not its bullets', async () => {
  const l = linkify(
    [
      '**Q9 (button syntax)** — I recommend `E`',
      '- **E:** corner brackets',
      '- **A:** guillemets',
      '【Q9: E* | A | D】',
    ].join('\n'),
  )
  expect(rows(l)).toEqual([['*Q9 (button syntax): E', 'Q9 (button syntax): A', 'Q9 (button syntax): D']])
})

test('no answer line, no buttons, whatever the question says', async () => {
  expect(rows(linkify('**Q2 (push):** Push to master? **yes** pushes, **no** waits.'))).toEqual([])
  expect(rows(linkify('**Q1 (a)** — I recommend `yes`\n- **yes:** y\n- **no:** n'))).toEqual([])
})

test("a row sits under a bulleted question, or at the line's own indent", async () => {
  expect(indents(linkify('- **Q2 (keep):** Keep it?\n【Q2: yes | no】'))).toEqual([2])
  expect(indents(linkify('- **Q2 (keep):** Keep it?\n    【Q2: yes | no】'))).toEqual([4])
  expect(indents(linkify('👀 **Needs you:** **Q1 (x):** Ok?\n【Q1: yes | no】'))).toEqual([0])
})

test('several questions each keep their own row', async () => {
  const l = linkify(
    [
      '👀 **Needs you:**',
      '- **Q7 (theme):** Set it?',
      '  【Q7: yes* | no】',
      '- **Q8 (push):** Push?',
      '  【Q8: yes | no*】',
    ].join('\n'),
  )
  expect(rows(l)).toEqual([
    ['*Q7 (theme): yes', 'Q7 (theme): no'],
    ['Q8 (push): yes', '*Q8 (push): no'],
  ])
})

test('an answer line with no label in the reply fills the bare ID', async () => {
  expect(rows(linkify('Still open.\n【Q3: keep | drop】'))).toEqual([['Q3: keep', 'Q3: drop']])
})

test('parseAnswers trims, unticks and skips empty answers', async () => {
  expect(parseAnswers(' `yes`* |  | no ', 'Q1 (a)')).toEqual([
    { label: 'yes', text: 'Q1 (a): yes', isPrimary: true },
    { label: 'no', text: 'Q1 (a): no', isPrimary: false },
  ])
})

test('brackets that are not a whole line stay text', async () => {
  const src = 'Write 【Q4: yes | no】 under it.'
  const l = linkify(src)
  expect(rows(l)).toEqual([])
  expect(markdown(l)).toEqual([src])
})

test('a bold question label is a link that fills the label', async () => {
  const l = linkify('**Q2 (push):** Push to master?')
  expect(fills(l)).toEqual(['Q2 (push): '])
  expect(markdown(l)[0]?.startsWith('**[Q2 (push)](https://reply-links.invalid/0):**')).toBe(true)
})

test('a Where-next item fills its own prompt text', async () => {
  const l = linkify('🧭 **Where next:**\n- N1 Finish the band\n- 💡 N2 Try **bold** idea\n- 🔮 N3: guess\n- N4 💡 Mark after')
  expect(fills(l)).toEqual(['Finish the band', 'Try bold idea', 'guess', 'Mark after'])
  expect(markdown(l)[0]?.split('\n')[2]).toBe('- 💡 [N2](https://reply-links.invalid/1) Try **bold** idea')
})

test('an N bullet outside the Where-next list is not a link', async () => {
  expect(linkify('👀 **Needs you:**\n- 💡 N1 and N2 are not committed yet.').actions.size).toBe(0)
  const l = linkify('🧭 **Where next:**\n- N1 go\n\n⏳ **Waiting on:** x\n- N2 not an item')
  expect(fills(l)).toEqual(['go'])
})

test('hammerspoon links get a placeholder that opens the real URL', async () => {
  const l = linkify('[[ 📋 copy ]](hammerspoon://copy?text=a%20b)')
  expect(fills(l)).toEqual(['open hammerspoon://copy?text=a%20b'])
  expect(markdown(l)).toEqual(['[[ 📋 copy ]](https://reply-links.invalid/0)'])
})

test('code spans and fences are left as written', async () => {
  const a = 'The parser reads `**Q1 (label)**` mid-line.'
  expect(markdown(linkify(a))).toEqual([a])
  const b = 'Write `[[ 📋 copy ]](hammerspoon://copy?text=x)` after it.'
  expect(markdown(linkify(b))).toEqual([b])
  const c = '```\n**Q1 (x):** Push?\n【Q1: yes | no】\n~~~\n```\nQ3 (turn on altera-dev) is answered.'
  const l = linkify(c)
  expect(l.actions.size).toBe(0)
  expect(rows(l)).toEqual([])
  expect(markdown(l)).toEqual([c])
  expect(rows(linkify('````\n```\n【Q1: yes | no】\n````'))).toEqual([])
})

test('addToBox fills, appends, completes a label and skips a repeat', async () => {
  expect(addToBox('', 'Q1 (a): yes')).toBe('Q1 (a): yes')
  expect(addToBox('hi', 'Q1 (a): yes')).toBe('hi\nQ1 (a): yes')
  expect(addToBox('hi\n', 'Q1 (a): yes')).toBe('hi\nQ1 (a): yes')
  expect(addToBox('Q1 (a): ', 'Q1 (a): yes')).toBe('Q1 (a): yes')
  expect(addToBox('x\nQ1 (a): yes', 'Q1 (a): yes')).toBe('x\nQ1 (a): yes')
})
