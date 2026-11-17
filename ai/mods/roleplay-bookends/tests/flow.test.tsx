// Event-flow tests for roleplay-bookends: prompt.submit, turn.start and
// turn.complete raised as a session raises them, then the rows drawn.
// Nothing here runs a process or a model: the hooks below answer for the
// engine (process.run, model.complete, session.id), and mock.clock runs the
// mod's $.clock.after(0, …) work when the test settles it.
import { expect, test } from 'claude-code/testing'
import type { Engine } from 'claude-code/testing'
import type { On } from 'claude-code'

import { start, world as baseWorld } from './world'
import type { World as BaseWorld } from './world'

// Markers the model's answer echoes, so a row shows whose opener it drew.
const MARKERS = ['ALPHA', 'BRAVO', 'CHARLIE']

type World = BaseWorld & { turnFor: Map<string, string> }

// The shared engine (./world). A prompt whose text is in `turnFor` starts that
// turn before prompt.submit resolves, as an idle prompt does in a session; any
// other prompt is folded into a running turn and starts none.
function world($: Engine, on: On): World {
  const turnFor = new Map<string, string>()
  const w = baseWorld($, on, {
    turnFor: text => turnFor.get(text),
    answer: prompt => {
      // The marker of the request itself, not of the previous reply it quotes.
      const asked = prompt.slice(prompt.lastIndexOf('asked:'))
      const kind = prompt.includes('OPENER') ? 'OPENER' : 'CLOSER'
      return `${kind} ${MARKERS.find(m => asked.includes(m)) ?? 'NONE'}`
    },
  })
  return Object.assign(w, { turnFor })
}

async function submit($: Engine, w: World, text: string, turnId?: string) {
  if (turnId) w.turnFor.set(text, turnId)
  await $.prompt.submit({ text, origin: { kind: 'composer' }, wait: false })
  await w.clock.settle()
}

// The bookend text drawn under a user row, or '' when there is none.
async function openerUnder($: Engine, shown: string): Promise<string> {
  const ui = await $.ui.mount({
    plugin: 'roleplay-bookends',
    surface: 'terminal',
    component: 'UserMessage',
    props: { text: shown, origin: { kind: 'composer' }, isExpanded: false },
  })
  const found = await ui.find({ type: 'Text', text: /OPENER/ })
  await ui.unmount()
  return found?.text ?? ''
}

async function closerUnder($: Engine, answer: string): Promise<string> {
  const ui = await $.ui.mount({
    plugin: 'roleplay-bookends',
    surface: 'terminal',
    component: 'AssistantMessage',
    props: { text: answer, isFirstOfReply: true },
  })
  const found = await ui.find({ type: 'Text', text: /CLOSER/ })
  await ui.unmount()
  return found?.text ?? ''
}

test('a prompt whose turn starts inside prompt.submit gets an opener and a closer', async ($, on) => {
  // The 2026-11-15 regression: the prompt was noted only after next(e), which
  // resolves after the turn has started, so no turn ever found it.
  const w = world($, on)
  await start($, w)
  const prompt = 'ALPHA please fix the queue matching in the mod'
  await submit($, w, prompt, 't1')
  expect(w.asks.filter(a => a.includes('OPENER'))).toHaveLength(1)
  expect(await openerUnder($, prompt)).toContain('OPENER ALPHA')

  const answer = 'Fixed it. The queue now matches.'
  await $.turn.complete({ answer, durationMs: 10, isAborted: false, turnId: 't1', reason: 'answer' })
  await w.clock.settle()
  expect(await closerUnder($, answer)).toContain('CLOSER ALPHA')
})

test('a prompt folded into a running turn does not take the next turn', async ($, on) => {
  // Review 2, finding 1: a typed prompt that starts no turn of its own must
  // not be what the next turn's opener is written for, even when it is a
  // substring of the next prompt ("y" in "yes, …").
  const w = world($, on)
  await start($, w)
  const folded = 'y'
  const next = 'yes BRAVO, now run the tests'
  await submit($, w, folded)
  await submit($, w, next, 't2')
  const openers = w.asks.filter(a => a.includes('OPENER'))
  expect(openers).toHaveLength(1)
  expect(openers[0]).toContain(`The user just asked:\n${next}`)
  expect(await openerUnder($, next)).toContain('OPENER BRAVO')
  expect(await openerUnder($, folded)).toBe('')
})

test('a paste row draws its own prompt opener, not a later one', async ($, on) => {
  // Review 2, finding 2: the row shows a placeholder while the prompt holds
  // the pasted text, so the row is matched by its typed pieces and line count.
  const w = world($, on)
  await start($, w)
  const pasted = Array.from({ length: 20 }, (_, i) => `ALPHA pasted line ${i + 1}`).join('\n')
  const withPaste = `fix ${pasted}`
  const later = 'fix the BRAVO queue matching please'
  await submit($, w, withPaste, 't1')
  await $.turn.complete({ answer: 'one', durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' })
  await w.clock.settle()
  await submit($, w, later, 't2')

  expect(await openerUnder($, 'fix [Pasted text #1 +20 lines]')).toContain('OPENER ALPHA')
  expect(await openerUnder($, later)).toContain('OPENER BRAVO')
  // A paste with no typed text around it would match every prompt: none drawn.
  expect(await openerUnder($, '[Pasted text #1 +20 lines]')).toBe('')
})
