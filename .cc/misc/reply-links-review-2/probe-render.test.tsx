// Review probes for register.tsx at c54f7411472c. Each asserts the correct
// result, so a failure is the bug. Copy the mod to a scratch folder, put this
// file in its tests/, and run `claude plugin test <copy>`.
import { expect, mock, test } from 'claude-code/testing'
import type { Engine } from 'claude-code/testing'
import type { On } from 'claude-code'

const mount = ($: Engine, text: string) =>
  $.ui.mount({ plugin: 'reply-links', surface: 'terminal', component: 'AssistantMessage', props: { text, isFirstOfReply: true } })

const CLEAR = [{ name: 'clear', description: '', source: 'builtin' as const }]

test('R1 a list that answers after the 1 s wait: the row appears once it does', async ($, on) => {
  let answer: (v: unknown) => void = () => undefined
  on('command.list', () => new Promise(r => { answer = r }).then(() => ({ value: CLEAR })))
  const clock = mock.clock(on)
  const mounting = mount($, 'Run /clear.')
  await clock.advance(1_000)
  const ui = await mounting
  expect(await ui.find({ key: 'c1-0' })).toBeUndefined()
  answer(undefined)
  await clock.advance(10)
  await ui.redraw()
  // Same props: does the drawing pick up the names now in the cache?
  expect((await ui.find({ key: 'c1-0' }))?.text).toBe('[ /clear ]')
  await ui.unmount()
})

test('R1b the same, with no redraw from outside: the row appears on its own', async ($, on) => {
  let answer: (v: unknown) => void = () => undefined
  on('command.list', () => new Promise(r => { answer = r }).then(() => ({ value: CLEAR })))
  const clock = mock.clock(on)
  const mounting = mount($, 'Run /clear.')
  await clock.advance(1_000)
  const ui = await mounting
  answer(undefined)
  await clock.advance(10)
  // A finished reply's props do not change, so nothing else redraws it.
  expect((await ui.find({ key: 'c1-0' }))?.text).toBe('[ /clear ]')
  await ui.unmount()
})

test('R9 a command with arguments clicked in one reply, then an answer in another reply', async ($, on) => {
  const box = { text: '' }
  on('prompt.read', () => ({ value: { text: box.text, cursor: box.text.length } }))
  on('prompt.fill', (_, e) => {
    box.text = e.mode === 'append' ? box.text + e.text : e.text
    return { isFilled: true, text: box.text, cursor: box.text.length }
  })
  on('command.list', () => ({ value: [{ name: 'code-review', description: '', source: 'builtin' as const }] }))
  const a = await mount($, 'Run `/code-review high`.')
  await a.press({ key: 'c1-0' })
  const b = await mount($, '**Q1 (go):** Go?\n【Q1: yes | no】')
  await b.press({ key: 'b1-0' })
  console.log(`R9 box=${JSON.stringify(box.text)}`)
  expect(box.text).toBe('Q1 (go): yes')
  await a.unmount()
  await b.unmount()
})

const sharedBox = (on: On) => {
  const box = { text: '' }
  on('prompt.read', () => ({ value: { text: box.text, cursor: box.text.length } }))
  on('prompt.fill', (_, e) => {
    box.text = e.mode === 'append' ? box.text + e.text : e.text
    return { isFilled: true, text: box.text, cursor: box.text.length }
  })
  return box
}

test('R9b a bare command clicked in one reply, then an answer in a reply with no slash', async ($, on) => {
  const box = sharedBox(on)
  on('command.list', () => ({ value: CLEAR }))
  const a = await mount($, 'Run /clear.')
  await a.press({ key: 'c1-0' })
  const b = await mount($, '**Q1 (go):** Go?\n【Q1: yes | no】')
  await b.press({ key: 'b1-0' })
  console.log(`R9b box=${JSON.stringify(box.text)}`)
  expect(box.text).toBe('Q1 (go): yes')
  await a.unmount()
  await b.unmount()
})

test('R9c a command with arguments, then an answer in a reply that holds a path', async ($, on) => {
  const box = sharedBox(on)
  on('command.list', () => ({ value: [{ name: 'code-review', description: '', source: 'builtin' as const }] }))
  const a = await mount($, 'Run `/code-review high`.')
  await a.press({ key: 'c1-0' })
  const b = await mount($, '**Q1 (go):** Check /Users/x?\n【Q1: yes | no】')
  await b.press({ key: 'b1-0' })
  console.log(`R9c box=${JSON.stringify(box.text)}`)
  expect(box.text).toBe('Q1 (go): yes')
  await a.unmount()
  await b.unmount()
})

test('R2c control: a reply with no slash, mounted as R2 mounts its second', async ($, on) => {
  const clock = mock.clock(on)
  let drawn = false
  const m = mount($, 'No commands here.').then(ui => { drawn = true; return ui })
  await clock.advance(0)
  console.log(`R2c drawnAfterAdvance0=${drawn}`)
  await (await m).unmount()
})

test('R2 an ask that never settles is asked again later, and a later draw does not wait 1 s again', async ($, on) => {
  let calls = 0
  on('command.list', () => {
    calls++
    return calls === 1 ? new Promise<never>(() => undefined) : { value: CLEAR }
  })
  const clock = mock.clock(on)
  const first = mount($, 'Run /clear.')
  await clock.advance(1_000)
  await (await first).unmount()
  // A second reply, drawn with no clock move: does it draw at all?
  let drawn = false
  const second = mount($, 'Then /clear again.').then(ui => { drawn = true; return ui })
  await clock.advance(0)
  const waitedAgain = !drawn
  await clock.advance(1_000)
  const ui = await second
  console.log(`R2 calls=${calls} waitedAgain=${waitedAgain} row=${(await ui.find({ key: 'c1-0' })) !== undefined}`)
  expect(calls).toBe(2)
  await ui.unmount()
})

test('R3 a refused clock.after with a list that answers: the row still draws', async ($, on) => {
  on('clock.after', () => ({ deny: 'no timers' }))
  on('command.list', () => ({ value: CLEAR }))
  const ui = await mount($, 'Run /clear.')
  expect((await ui.find({ key: 'c1-0' }))?.text).toBe('[ /clear ]')
  await ui.unmount()
})

test('R4 a refused clock.after with a list that never answers: the reply still draws', { timeoutMs: 4000 }, async ($, on) => {
  on('clock.after', () => ({ deny: 'no timers' }))
  on('command.list', () => new Promise<never>(() => undefined))
  const ui = await mount($, 'Run /clear.')
  expect(await ui.find({ key: 'submit' })).toBeDefined()
  await ui.unmount()
})

const blanker = {
  name: 'blanker',
  tier: 'append' as const,
  register(on: On) {
    on('ui.render', { component: 'AssistantMessage' }, async ($, e, next) =>
      next({ ...e, props: { ...e.props, text: '' } }),
    )
  },
}

test('R5 a block a mod beneath empties draws no lone submit button', { plugins: [blanker] }, async $ => {
  const ui = await mount($, 'Just prose.')
  console.log('R5 buttons', JSON.stringify((await ui.findAll({ type: 'Button' })).map(b => b.text)))
  expect(await ui.find({ key: 'submit' })).toBeUndefined()
  await ui.unmount()
})

test('R6 a plain https link in a plain reply is left to the surface', async $ => {
  const ui = await mount($, 'See [docs](https://example.com).')
  const md = await ui.find({ type: 'Markdown' })
  console.log('R6 markdown', JSON.stringify(md))
  let res: unknown
  try {
    res = await ui.press({ key: 'md0', link: { href: 'https://example.com' } })
  } catch (err) {
    res = `rejected: ${String(err)}`
  }
  console.log('R6 press', JSON.stringify(res))
  await ui.unmount()
})

test('R7 every block of one reply gets its own submit button', async $ => {
  const a = await mount($, 'Let me read the file.')
  const b = await $.ui.mount({ plugin: 'reply-links', surface: 'terminal', component: 'AssistantMessage', props: { text: 'Done.', isFirstOfReply: false } })
  const n = (await a.findAll({ key: 'submit' })).length + (await b.findAll({ key: 'submit' })).length
  console.log(`R7 submit buttons across two blocks of one reply: ${n}`)
  await a.unmount()
  await b.unmount()
})
