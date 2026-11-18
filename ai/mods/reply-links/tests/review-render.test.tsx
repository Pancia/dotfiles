// Review repros for drawing, presses and the system-prompt section.
import { expect, test } from 'claude-code/testing'
import type { Engine } from 'claude-code/testing'
import type { On } from 'claude-code'

const mount = ($: Engine, text: string, extra: Record<string, unknown> = {}) =>
  $.ui.mount({
    plugin: 'reply-links',
    surface: 'terminal',
    component: 'AssistantMessage',
    props: { text, isFirstOfReply: true },
    ...extra,
  } as never)

const FS = { viewport: { columns: 100, rows: 40, isFullscreen: true } }

test('G1 the main screen falls back to the engine', async $ => {
  const ui = await mount($, '**Q2 (push):** Push?\n【Q2: yes | no】', {
    viewport: { columns: 100, rows: 40, isFullscreen: false },
  })
  expect((await ui.findAll({ type: 'Button' })).length).toBe(0)
  await ui.unmount()
})

test('G2 the desktop surface falls back to the engine', async $ => {
  const ui = await $.ui.mount({
    plugin: 'reply-links',
    surface: 'desktop',
    component: 'AssistantMessage',
    props: { text: '**Q2 (push):** Push?\n【Q2: yes | no】', isFirstOfReply: true },
  })
  expect((await ui.findAll({ type: 'Button' })).length).toBe(0)
  await ui.unmount()
})

test('E1 an answer whose label is empty after cleaning still draws', async $ => {
  const ui = await mount($, '**Q1 (a):** Ok?\n【Q1: `` | no】', FS)
  let err = ''
  try {
    await ui.drawn()
  } catch (x) {
    err = String(x)
  }
  const bs = await ui.findAll({ type: 'Button' })
  expect(err).toBe('')
  expect(bs.every(b => typeof b.props.label === 'string' && b.props.label !== '')).toBe(true)
  await ui.unmount()
})

test('E2 a tab inside an answer still draws', async $ => {
  const ui = await mount($, '**Q1 (a):** Ok?\n【Q1: a\tb | no】', FS)
  let err = ''
  try {
    await ui.drawn()
  } catch (x) {
    err = String(x)
  }
  expect(err).toBe('')
  await ui.unmount()
})

test('E3 a reply with more than 256 links still gets its links', async $ => {
  const lines: string[] = []
  for (let i = 1; i <= 300; i++) lines.push(`- **Q${i} (item ${i}):** Ok?`)
  const ui = await mount($, lines.join('\n'), FS)
  let err = ''
  try {
    await ui.drawn()
  } catch (x) {
    err = String(x)
  }
  const md = await ui.findAll({ type: 'Markdown' })
  expect(err).toBe('')
  await ui.unmount()
})

test('F1 a refused fill tells the person', async ($, on) => {
  const toasts: string[] = []
  on('ui.toast', (_, e) => {
    toasts.push(JSON.stringify(e))
    return { value: undefined } as never
  })
  on('prompt.read', () => ({ value: { text: '', cursor: 0 } }))
  on('prompt.fill', () => ({ isFilled: false, refusal: 'dialog' as const }))
  const ui = await mount($, '**Q2 (push):** Push?\n【Q2: yes | no】', FS)
  await ui.press({ key: 'b1-0' })
  expect(toasts.length).toBe(1)
  await ui.unmount()
})

test('F2 a fill that throws does not reject the press', async ($, on) => {
  on('prompt.read', () => ({ value: { text: '', cursor: 0 } }))
  on('prompt.fill', () => {
    throw new Error('fill broke')
  })
  const ui = await mount($, '**Q2 (push):** Push?\n【Q2: yes | no】', FS)
  let err = ''
  try {
    const r = await ui.press({ key: 'b1-0' })
  } catch (x) {
    err = String(x)
  }
  // still drawn and pressable after?
  const bs = await ui.findAll({ type: 'Button' })
  expect(err).toBe('')
  await ui.unmount()
})

test('F3 a plain append keeps the draft (mode append, not replace)', async ($, on) => {
  const modes: string[] = []
  on('prompt.read', () => ({ value: { text: 'my draft', cursor: 8 } }))
  on('prompt.fill', (_, e) => {
    modes.push(e.mode)
    return { isFilled: true, text: e.text, cursor: 0 }
  })
  const ui = await mount($, '**Q2 (push):** Push?\n【Q2: yes | no】', FS)
  await ui.press({ key: 'b1-0' })
  expect(modes).toEqual(['append'])
  await ui.unmount()
})

const compose = ($: Engine, surfaces: string[], traits: string[] = []) =>
  $.prompt.compose({ model: 'claude-opus-5-5', promptModel: 'claude-opus-5-5', surfaces, tools: [], outputStyle: null, traits } as never)

test('C1 teammate and bare sessions get no rule', async ($, on) => {
  on('prompt.compose', () => ({ sections: [{ id: 'intro', text: 'hi', scope: 'shared' as const }] }))
  for (const t of ['teammate', 'bare']) {
    expect((await compose($, ['terminal'], [t])).sections.map(s => s.id)).toEqual(['intro'])
  }
})

test('C2 a session that speaks through a message tool gets no rule', async ($, on) => {
  on('prompt.compose', () => ({ sections: [{ id: 'intro', text: 'hi', scope: 'shared' as const }] }))
  expect((await compose($, ['terminal'], ['send-user-message'])).sections.map(s => s.id)).toEqual(['intro'])
})

test('C3 the rule is added once even when composed twice through the chain', async ($, on) => {
  on('prompt.compose', () => ({ sections: [{ id: 'intro', text: 'hi', scope: 'shared' as const }] }))
  const ids = (await compose($, ['terminal', 'desktop'])).sections.map(s => s.id)
  expect(ids.filter(i => i === 'reply-links:answer-buttons').length).toBe(1)
})
