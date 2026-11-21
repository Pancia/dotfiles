import { expect, test } from 'claude-code/testing'

import { addToBox, commandToBox, isLoneCommand, linkify, mayHaveCommand, parseAnswers } from '../hooks/linkify'
import type { Linked } from '../hooks/linkify'

const fills = (l: Linked) =>
  [...l.actions.values()].map(a => (a.kind === 'open' ? `open ${a.url}` : a.kind === 'command' ? `run ${a.text}` : a.text))

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

test('a Where-next item fills its bare ID', async () => {
  const l = linkify('🧭 **Where next:**\n- N1 Finish the band\n- 💡 N2 Try **bold** idea\n- 🔮 N3: guess\n- N4 💡 Mark after')
  expect(fills(l)).toEqual(['N1', 'N2', 'N3', 'N4'])
  const items = l.segments.flatMap(s => (s.kind === 'item' ? [`${s.lead}${s.mark}|${s.id}|${s.rest}`] : []))
  expect(items).toEqual(['- |N1|Finish the band', '- 💡|N2|Try **bold** idea', '- 🔮|N3|guess', '- |N4|💡 Mark after'])
  expect(markdown(l)).toEqual(['🧭 **Where next:**'])
})

test('a wrapped Where-next line joins its item, and its links still answer', async () => {
  const l = linkify('🧭 **Where next:**\n  - N1 a long item\n    [[ 📋 copy ]](hammerspoon://copy?text=x)\n- N2 second\n\n👀 **Needs you:** none')
  const items = l.segments.flatMap(s => (s.kind === 'item' ? [[s.indent, s.rest, s.hrefs.length]] : []))
  expect(items).toEqual([
    [2, 'a long item [[ 📋 copy ]](https://reply-links.invalid/1)', 1],
    [0, 'second', 0],
  ])
  expect(markdown(l)).toEqual(['🧭 **Where next:**', '👀 **Needs you:** none'])
})

test('an N bullet outside the Where-next list is not a link', async () => {
  expect(linkify('👀 **Needs you:**\n- 💡 N1 and N2 are not committed yet.').actions.size).toBe(0)
  const l = linkify('🧭 **Where next:**\n- N1 go\n\n⏳ **Waiting on:** x\n- N2 not an item')
  expect(fills(l)).toEqual(['N1'])
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

const CMDS = new Set(['cc:retro', 'clear', 'code-review'])

const cmdRows = (l: Linked) =>
  l.segments.flatMap(s => (s.kind === 'commands' ? [`${s.indent}:${s.commands.join(' ')}`] : []))

test('a row of command buttons follows each paragraph or list that names them', async () => {
  const l = linkify(
    [
      'Run `/cc:retro`, then /clear, then `/cc:retro` again.',
      'Same paragraph.',
      '',
      'No commands here.',
      '',
      '  - try /clear',
      '  - or `/code-review high`',
      '',
      '**Q1 (go):** Run /clear?',
      '【Q1: yes | no】',
    ].join('\n'),
    CMDS,
  )
  expect(cmdRows(l)).toEqual(['0:/cc:retro /clear', '2:/clear /code-review high', '0:/clear'])
  // The question's row comes after its answer buttons, not between them.
  expect(l.segments.map(s => s.kind)).toEqual(['markdown', 'commands', 'markdown', 'commands', 'markdown', 'buttons', 'commands'])
})

const kinds = (l: Linked) => l.segments.map(s => s.kind)

test('a list item that goes on past a blank line or holds a fence is not split', async () => {
  const cont = linkify('1. Run /clear\n\n    More text of step 1.\n\nAfter.', CMDS)
  expect(markdown(cont)).toEqual(['1. Run /clear\n\n    More text of step 1.', 'After.'])
  expect(kinds(cont)).toEqual(['markdown', 'commands', 'markdown'])

  const fenced = linkify('- outer\n  - Run /clear, then:\n    ```sh\n    ls\n    ```\n  - next', CMDS)
  expect(kinds(fenced)).toEqual(['markdown', 'commands'])

  const loose = linkify('1. Run /clear\n\n2. Then `/cc:retro`\n\n3. Done', CMDS)
  expect(kinds(loose)).toEqual(['markdown', 'commands'])
  expect(cmdRows(loose)).toEqual(['0:/clear /cc:retro'])
})

test('a paragraph ends at a heading, the Where-next line and a margin fence', async () => {
  expect(cmdRows(linkify('## Use /clear\nBody `/cc:retro`', CMDS))).toEqual(['0:/clear', '0:/cc:retro'])
  const wn = linkify('Run /clear.\n🧭 **Where next:**\n- N1 a\n- N2 b\n\n👀 **Needs you:** none', CMDS)
  expect(kinds(wn)).toEqual(['markdown', 'commands', 'markdown', 'item', 'item', 'markdown'])
  // After a fence at the margin, the next block takes its own indent.
  expect(cmdRows(linkify('  - try /clear\n```\nx\n```\nthen /cc:retro', CMDS))).toEqual(['2:/clear', '0:/cc:retro'])
  // And after a list item's own fence, text at the margin starts a block.
  expect(cmdRows(linkify('  - try /clear\n  ```\n  x\n  ```\nthen /cc:retro', CMDS))).toEqual(['2:/clear', '0:/cc:retro'])
})

test('blank lines between Where-next items put no row between them', async () => {
  const l = linkify('🧭 **Where next:**\n- N1 run /clear\n\n- N2 b\n\n✅ done', CMDS)
  expect(kinds(l)).toEqual(['markdown', 'item', 'item', 'commands', 'markdown'])
})

test('a word, a glob, a file name or code that is not prose gets no button', async () => {
  const none = [
    'edit /config.json and /clear.md',
    'src/**/clear and see `ai/mods`/clear here',
    '[doc]: /clear',
    '> /clear in a quote',
    'Example:',
    '',
    '    /clear',
  ].join('\n')
  expect(cmdRows(linkify(none, new Set([...CMDS, 'config'])))).toEqual([])
  // Bold, italic, a sentence's end and a "(" still count.
  expect(cmdRows(linkify('**/clear** then _/cc:retro_.', CMDS))).toEqual(['0:/clear /cc:retro'])
  expect(cmdRows(linkify('(or /clear)', CMDS))).toEqual(['0:/clear'])
})

test('a glob, a comment or indented code anywhere gets no button', async () => {
  const none = [
    'matches **/clear files and _/clear here',
    '<!-- /clear -->',
    '<!--',
    'run /clear',
    '-->',
  ].join('\n')
  expect(cmdRows(linkify(none, CMDS))).toEqual([])
  // Indented code at the reply's start, after a heading, after a fence, in an item.
  expect(cmdRows(linkify('    /clear\nText.', CMDS))).toEqual([])
  expect(cmdRows(linkify('## Example\n    /clear', CMDS))).toEqual([])
  expect(cmdRows(linkify('```\nx\n```\n    /clear', CMDS))).toEqual([])
  expect(cmdRows(linkify('- step one:\n\n        /clear', CMDS))).toEqual([])
  // Text of the item, at its own indent, still counts.
  expect(cmdRows(linkify('- step one:\n\n  then /clear', CMDS))).toEqual(['0:/clear'])
})

test('a command inside a question label gets a row, and no link of its own', async () => {
  const l = linkify('**Q3 (run /clear):** Clear now?', CMDS)
  expect(fills(l)).toEqual(['Q3 (run /clear): '])
  expect(cmdRows(l)).toEqual(['0:/clear'])
})

test('a known command, in prose or code, joins the row; the text is left as written', async () => {
  const src = 'When convenient: run `/cc:retro`. Or type /clear, or `/code-review high`.'
  const l = linkify(src, CMDS)
  expect(cmdRows(l)).toEqual(['0:/cc:retro /clear /code-review high'])
  expect(markdown(l)).toEqual([src])
  expect(fills(l)).toEqual([])
})

test('a fence ends the block, and the end of the reply gets its row', async () => {
  const l = linkify('Run /clear\n```\n/clear\n```\nthen `/cc:retro`', CMDS)
  expect(cmdRows(l)).toEqual(['0:/clear', '0:/cc:retro'])
})

test('an unknown name, a path, a URL or a fenced block stays as it is', async () => {
  const src = [
    'See /usr/bin and `/usr/bin`, a/clear, https://x.io/clear and [doc](/clear).',
    '```',
    '/clear',
    '```',
  ].join('\n')
  expect(cmdRows(linkify(src, CMDS))).toEqual([])
  expect(cmdRows(linkify('run /clear', new Set()))).toEqual([])
})

test('mayHaveCommand spots a candidate cheaply', async () => {
  expect(mayHaveCommand('run `/cc:retro`')).toBe(true)
  expect(mayHaveCommand('a\n/clear')).toBe(true)
  expect(mayHaveCommand('- N1—/clear')).toBe(true)
  expect(mayHaveCommand('no commands, a/1 here')).toBe(false)
})

test('a command goes in an empty box or replaces a lone command, never a draft', async () => {
  const offered = ['/code-review high']
  const put = (box: string) => commandToBox(box, '/cc:retro', CMDS, offered)
  expect(put('')).toBe('/cc:retro')
  expect(put('/clear')).toBe('/cc:retro')
  expect(put('/code-review high')).toBe('/cc:retro')
  expect(put('my draft')).toBe(null)
  expect(put('/clear\nmore')).toBe(null)
  expect(put('/Users/anthony/x.log shows an error, why?')).toBe(null)
  expect(put('/code-review high focus on auth')).toBe(null)
  expect(put('/unknown')).toBe(null)
  expect(isLoneCommand(' /clear \n', CMDS, [])).toBe(true)
})
