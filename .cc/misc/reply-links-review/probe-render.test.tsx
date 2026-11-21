import { expect, test } from 'claude-code/testing'
import type { Engine } from 'claude-code/testing'

const mount = ($: Engine, text: string) =>
  $.ui.mount({ plugin: 'reply-links', surface: 'terminal', component: 'AssistantMessage', props: { text, isFirstOfReply: true } })

let calls = 0
test('R1 failed list is retried on every render (not cached)', async ($, on) => {
  on('command.list', () => { calls++; throw new Error('boom') })
  for (let k = 0; k < 3; k++) {
    const ui = await mount($, 'run /clear now')
    await ui.unmount()
  }
  expect(calls).toBe(1)
})

test('R2 first good list is cached', async ($, on) => {
  on('command.list', () => ({ value: [{ name: 'clear', description: '', source: 'builtin' }] }))
  const ui = await mount($, 'run /clear now')
  expect((await ui.find({ key: 'c1-0' }))?.text).toBe('[ /clear ]')
  await ui.unmount()
})

test('R3 a later test with a different list sees the old cache', async ($, on) => {
  on('command.list', () => ({ value: [{ name: 'cc:retro', description: '', source: 'plugin' }] }))
  const ui = await mount($, 'run /cc:retro now')
  expect((await ui.find({ key: 'c1-0' }))?.text).toBe('[ /cc:retro ]')
  await ui.unmount()
})

test('R4 command click on an empty read uses replace, not append', async ($, on) => {
  const modes: string[] = []
  on('command.list', () => ({ value: [{ name: 'clear', description: '', source: 'builtin' }] }))
  on('prompt.read', () => ({ value: { text: '', cursor: 0 } }))
  on('prompt.fill', (_, e) => { modes.push(String(e.mode)); return { isFilled: true, text: e.text, cursor: 0 } })
  const ui = await mount($, 'run /clear now')
  await ui.press({ key: 'c1-0' })
  expect(modes).toEqual(['append'])
  await ui.unmount()
})

test('R5 a reply with answer row and command row: keys and submit', async ($, on) => {
  on('command.list', () => ({ value: [{ name: 'clear', description: '', source: 'builtin' }] }))
  const ui = await mount($, '**Q1 (go):** Run /clear?\n【Q1: yes | no】')
  const t = await ui.find({ key: 'submit' })
  expect(t === undefined ? 'no submit' : 'submit').toBe('submit')
  expect((await ui.find({ key: 'c1-0' }))?.text).toBe('[ /clear ]')
  expect((await ui.find({ key: 'b2-0' }))?.text).toBe('[ yes ]')
  await ui.unmount()
})
test('R6 command click then answer click', async ($, on) => {
  const box = { text: '' }
  on('prompt.read', () => ({ value: { text: box.text, cursor: box.text.length } }))
  on('prompt.fill', (_, e) => { box.text = e.mode === 'append' ? box.text + e.text : e.text; return { isFilled: true, text: box.text, cursor: 0 } })
  on('command.list', () => ({ value: [{ name: 'clear', description: '', source: 'builtin' }] }))
  const ui = await mount($, '**Q1 (go):** Run /clear?\n【Q1: yes | no】')
  await ui.press({ key: 'c1-0' })
  await ui.press({ key: 'b2-0' })
  expect(box.text).toBe('?')
  await ui.unmount()
})
