import { expect, test } from 'claude-code/testing'
import { commandToBox, linkify } from '../hooks/linkify'
import type { Linked } from '../hooks/linkify'

const CMDS = new Set(['cc:retro', 'clear', 'code-review', 'review', 'config'])
const show = (l: Linked) =>
  JSON.stringify(l.segments.map(s => (s.kind === 'markdown' ? `md:${s.text}` : s.kind === 'commands' ? `cmds@${s.indent}:${s.commands.join(' ')}` : s.kind)))

test('X1 draft that starts with a path is kept', () => {
  expect(commandToBox('/Users/anthony/x.log shows an error, why?', '/cc:retro')).toBe(null)
})
test('X2 typed command with own args kept', () => {
  expect(commandToBox('/code-review high focus on auth', '/clear')).toBe(null)
})
test('X3 four-space continuation after split', () => {
  expect(show(linkify('1. Run /clear\n\n    More text of step 1.', CMDS))).toBe('?')
})
test('X3b no command: no split', () => {
  expect(show(linkify('1. Run clear\n\n    More text of step 1.', CMDS))).toBe('?')
})
test('X4 fence inside list item', () => {
  expect(show(linkify('- outer\n  - Run /clear, then:\n    ```sh\n    ls\n    ```\n  - next', CMDS))).toBe('?')
})
test('X5 span then slash', () => {
  expect(show(linkify('see `ai/mods`/clear here', CMDS))).toBe('?')
})
test('X6 glob', () => {
  expect(show(linkify('matches src/**/review and **/clear files', CMDS))).toBe('?')
})
test('X7 reference link def', () => {
  expect(show(linkify('[doc]: /clear', CMDS))).toBe('?')
})
test('X8 indented code block', () => {
  expect(show(linkify('Example:\n\n    /clear\n', CMDS))).toBe('?')
})
test('X9 file extension', () => {
  expect(show(linkify('edit /config.json and /review.md', CMDS))).toBe('?')
})
test('X10 label with command', () => {
  expect(show(linkify('**Q3 (run /clear):** Clear now?', CMDS))).toBe('?')
})
test('X11 where-next with blank lines', () => {
  expect(show(linkify('🧭 **Where next:**\n- N1 run /clear\n\n- N2 run `/cc:retro`\n  more words\n\n👀 **Needs you:** none', CMDS))).toBe('?')
})
test('X12 after fence indent', () => {
  expect(show(linkify('  - try /clear\n  ```\n  x\n  ```\nthen /cc:retro', CMDS))).toBe('?')
})
test('X13 quoted fence', () => {
  expect(show(linkify('> ```\n> /clear\n> ```', CMDS))).toBe('?')
})
test('X14 heading then text', () => {
  expect(show(linkify('## Use /clear\nBody /review', CMDS))).toBe('?')
})
test('X15 html comment / angle', () => {
  expect(show(linkify('<code>/clear</code> and </clear>', CMDS))).toBe('?')
})
test('X16 ordered loose list', () => {
  expect(show(linkify('1. Run /clear\n\n2. Then /review\n\n3. Done', CMDS))).toBe('?')
})
test('X17 needs-you inline', () => {
  expect(show(linkify('Text /clear\n👀 **Needs you:** run `/cc:retro`', CMDS))).toBe('?')
})
import { mayHaveCommand } from '../hooks/linkify'
test('X18 paragraph directly above Where-next', () => {
  expect(show(linkify('Run /clear.\n🧭 **Where next:**\n- N1 a\n- N2 b\n\n👀 **Needs you:** none', CMDS))).toBe('?')
})
test('X19 wrapped item names a command', () => {
  expect(show(linkify('🧭 **Where next:**\n- N1 a long item\n  then run /clear\n- N2 b\n\n👀 **Needs you:** none', CMDS))).toBe('?')
})
test('X20 mayHaveCommand vs N-item dash', () => {
  const src = '🧭 **Where next:**\n- N1—/clear'
  expect(`${mayHaveCommand(src)} ${show(linkify(src, CMDS))}`).toBe('?')
})
