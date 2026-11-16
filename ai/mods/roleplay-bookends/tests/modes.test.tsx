// Tests for the two modes (/roleplay session|random), the Reroll and Pick
// controls above the prompt, the Pick pane, and the odds drawn in random
// mode. As in flow.test.tsx, the hooks below answer for the engine: nothing
// runs a process or a model.
import { expect, mock, test } from 'claude-code/testing'
import type { Engine, MockClock } from 'claude-code/testing'
import type { On } from 'claude-code'

import { matches, parseRoster, pct, pickChar } from '../hooks/register'

const TAG = '[🎭 Character Roll: «Togusa» 🔍 GHOST IN THE SHELL — Methodical · earnest || vote id: ab12]'
const ROLL = JSON.stringify({ hookSpecificOutput: { hookEventName: 'UserPromptSubmit', additionalContext: TAG } })
// What `roleplay-roll --roster` prints for a three-character cast.
const ROSTER = [
  ['GHOST IN THE SHELL', 'Togusa', '🔍', 'Methodical · earnest', '', '0.085106', '0.012158'],
  ['WARHAMMER 40K', 'Commissar', '💀', 'Stern', "'For the Emperor!'", '0.085106', '0.014184'],
  ['FAVORITES', 'Holo', '🐺', 'Wise wolf', '', '0.250000', '0.020000'],
].map(r => r.join('\t')).join('\n') + '\n'
const USAGE = { input_tokens: 1, output_tokens: 1, cache_read_input_tokens: 0, cache_creation_input_tokens: 0 }

type World = {
  clock: MockClock; asks: string[]; rolls: string[]; toasts: string[]; panes: string[]
  // The mod's $.store, the current session id, and how many --roster runs
  // fail before one answers.
  store: Map<string, unknown>; sid: string; rosterFails: number
  registered: { name: string; immediate?: true }[]
}

function world($: Engine, on: On, saved?: string): World {
  const clock = mock.clock(on, { now: 1_000_000 })
  const w: World = {
    clock, asks: [], rolls: [], toasts: [], panes: [], store: new Map(), sid: 'sess-1', rosterFails: 0, registered: [],
  }
  if (saved) w.store.set('mode', saved)
  on('process.run', (_, e) => {
    const cmd = e.argv.join(' ')
    if (cmd.includes('roleplay-roll')) w.rolls.push(cmd)
    if (cmd.includes('--roster') && w.rosterFails > 0) {
      w.rosterFails--
      throw new Error('timed out')
    }
    const stdout = cmd.includes('--roster') ? ROSTER : cmd.includes('roleplay-roll') ? ROLL : ''
    return { value: { exitCode: 0, stdout, stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
  })
  on('model.complete', (_, e) => {
    w.asks.push(e.prompt)
    const kind = e.prompt.includes('OPENER') ? 'OPENER' : 'CLOSER'
    return { value: { isAnswered: true as const, text: `${kind} line`, usage: USAGE } }
  })
  on('session.id', () => ({ value: w.sid }))
  on('command.register', (_, e) => {
    w.registered.push({ name: e.name, ...(e.immediate ? { immediate: e.immediate } : {}) })
    return { value: { command: e.name } }
  })
  on('store.get', (_, e) => ({ value: structuredClone(w.store.get(e.key)) }))
  on('store.set', (_, e) => {
    w.store.set(e.key, structuredClone(e.value))
    return { value: undefined }
  })
  on('ui.panes', () => ({
    value: w.panes.map(id => ({ id, title: id, isShown: true, isFocused: true, isPlaced: true })),
  }))
  on('ui.toast', (_, e) => {
    w.toasts.push(e.text)
    return { value: undefined }
  })
  on('ui.open', (_, e) => {
    w.panes.push(e.id)
    return { value: { isPlaced: true } }
  })
  on('ui.close', (_, e) => {
    w.panes = w.panes.filter(p => p !== e.id)
    return { value: undefined }
  })
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('session.end', (_, e) => ({ sessionId: e.sessionId }))
  on('prompt.submit', async (_, e) => {
    await $.turn.start({ text: e.text, turnId: `t-${e.text.length}` })
    return { text: e.text }
  })
  on('turn.start', (_, e) => ({ turnId: e.turnId }))
  on('turn.complete', (_, e) => ({ text: e.answer }))
  return w
}

async function start($: Engine, w: World) {
  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })
  await w.clock.settle()
}

async function submit($: Engine, w: World, text: string) {
  await $.prompt.submit({ text, origin: { kind: 'composer' }, wait: false })
  await w.clock.settle()
}

// /roleplay <args>, as typed at the prompt.
async function run($: Engine, args: string) {
  return $.command.run({
    command: 'roleplay', args, origin: { kind: 'composer' }, presentation: { isFullscreen: true, columns: 120 },
  })
}

async function opener($: Engine, shown: string) {
  return $.ui.mount({
    plugin: 'roleplay-bookends',
    surface: 'terminal',
    component: 'UserMessage',
    props: { text: shown, origin: { kind: 'composer' }, isExpanded: false },
  })
}

const BAND = {
  plugin: 'roleplay-bookends',
  surface: 'terminal',
  component: 'AbovePrompt',
  props: {
    hasSurvey: false, isCollapsed: false, isWorking: false, maxRows: 10, bodyColumns: 100,
    scroll: { offset: 0, bodyRows: 10 }, view: {},
  },
} as const

const PANE = {
  plugin: 'roleplay-bookends',
  surface: 'terminal',
  component: 'Pane',
  requestId: 'roleplay-pick',
  props: {
    title: 'Pick a character', isFocused: true, bodyColumns: 60, placement: 'inline',
    scroll: { offset: 0, bodyRows: 20 }, view: {},
  },
} as const

test('the roster rows parse, and anything else gives none', () => {
  const rows = parseRoster(ROSTER)
  expect(rows).toHaveLength(3)
  expect(rows[1]).toEqual({
    universe: 'WARHAMMER 40K', name: 'Commissar', emoji: '💀', traits: 'Stern',
    sig: "'For the Emperor!'", u: 0.085106, c: 0.014184,
  })
  expect(parseRoster(ROLL)).toEqual([])
  expect(parseRoster('')).toEqual([])
})

test('a share prints as a short percent', () => {
  expect(pct(0.085106)).toBe('8.5%')
  expect(pct(0.012158)).toBe('1.2%')
  expect(pct(0.0018)).toBe('0.18%')
  expect(pct(0.25)).toBe('25%')
  expect(pct(0.03)).toBe('3%')
})

test('the search matches every word in a name or universe', () => {
  const all = parseRoster(ROSTER)
  expect(matches(all, '').map(c => c.name)).toEqual(['Togusa', 'Commissar', 'Holo'])
  expect(matches(all, 'ghost tog').map(c => c.name)).toEqual(['Togusa'])
  expect(matches(all, 'WARHAMMER').map(c => c.name)).toEqual(['Commissar'])
  expect(matches(all, 'nobody')).toEqual([])
})

test('a weighted pick follows the overall shares and can skip one name', () => {
  const all = parseRoster(ROSTER)
  // Togusa holds the first 0.012158 of 0.046342 (26%), Holo the last 43%.
  expect(pickChar(all, 0)?.name).toBe('Togusa')
  expect(pickChar(all, 0.25)?.name).toBe('Togusa')
  expect(pickChar(all, 0.3)?.name).toBe('Commissar')
  expect(pickChar(all, 0.99)?.name).toBe('Holo')
  expect(pickChar(all, 0, 'Togusa')?.name).toBe('Commissar')
  expect(pickChar([], 0.5)).toBe(null)
})

test('random mode draws the odds beside the name and universe, with the vote links', async ($, on) => {
  const w = world($, on)
  await start($, w)
  await submit($, w, 'please fix the parser')
  const ui = await opener($, 'please fix the parser')
  expect((await ui.find({ type: 'Text', text: '1.2% ' }))?.text).toBe('1.2% ')
  expect((await ui.find({ type: 'Text', text: '8.5% ' }))?.text).toBe('8.5% ')
  expect(await ui.findAll({ type: 'Link' })).toHaveLength(4)
  await ui.unmount()
  expect(w.rolls.some(r => r.includes('--votes'))).toBe(true)
  // The row above the prompt is always there: mode button and Pick, no Reroll.
  const band = await $.ui.mount(BAND)
  expect((await band.findAll({ type: 'Button' })).map(b => b.text)).toEqual(['random'])
  expect((await band.find({ type: 'Text', text: /new character each prompt/ }))?.text).toBe('a new character each prompt')
  await band.unmount()
})

test('the mode button switches mode, saves the default, and shows Reroll in session mode', async ($, on) => {
  const w = world($, on)
  await start($, w)
  expect(w.registered).toEqual([{ name: 'roleplay', immediate: true }])
  const band = await $.ui.mount(BAND)
  await band.press({ key: 'rp-mode' })
  await w.clock.settle()
  expect(w.store.get('mode')).toBe('session')
  expect((await band.findAll({ type: 'Button' })).map(b => b.text)).toEqual(['session', 'Reroll', 'Pick'])
  expect((await band.find({ type: 'Text', text: /«/ }))?.text).toMatch(/^«/)
  await band.press({ key: 'rp-mode' })
  await w.clock.settle()
  expect(w.store.get('mode')).toBe('random')
  expect((await band.findAll({ type: 'Button' })).map(b => b.text)).toEqual(['random'])
  await band.unmount()
})

test('a roster load that fails is tried again at the next need', async ($, on) => {
  const w = world($, on)
  w.rosterFails = 1
  await start($, w)
  await submit($, w, 'first prompt after a slow start')
  const ui = await opener($, 'first prompt after a slow start')
  expect((await ui.find({ type: 'Text', text: '1.2% ' }))?.text).toBe('1.2% ')
  await ui.unmount()
  expect(w.rolls.filter(r => r.includes('--roster')).length).toBeGreaterThanOrEqual(2)
})

test('a resumed session gets its saved mode and character back', async ($, on) => {
  const w = world($, on, 'random')
  const holo = parseRoster(ROSTER)[2]!
  w.store.set('pins', { 'sess-1': { mode: 'session', who: holo } })
  await start($, w)
  const band = await $.ui.mount(BAND)
  expect((await band.find({ type: 'Text', text: /«/ }))?.text).toBe('«Holo» 🐺 FAVORITES')
  await band.unmount()
  await submit($, w, 'carry on')
  expect(w.asks.find(a => a.includes('OPENER'))).toContain('Character: Holo (FAVORITES)')
})

test('/clear gives a session-mode session a new character, saved under the new id', async ($, on) => {
  const w = world($, on, 'session')
  await start($, w)
  const first = (w.store.get('pins') as Record<string, { who: { name: string } }>)['sess-1']?.who.name
  expect(first).toBeDefined()
  w.sid = 'sess-2'
  await $.session.end({ reason: 'clear', sessionId: 'sess-1', resume: { id: 'sess-1' } })
  await w.clock.settle()
  const pins = w.store.get('pins') as Record<string, { mode: string; who: { name: string } | null }>
  expect(pins['sess-2']?.mode).toBe('session')
  expect(pins['sess-2']?.who?.name).toBeDefined()
  // The old session's pin is left as it was, for a later resume.
  expect(pins['sess-1']?.who?.name).toBe(first)
})

test('a real exit rolls nothing', async ($, on) => {
  const w = world($, on, 'session')
  await start($, w)
  const before = w.store.get('pins')
  await $.session.end({ reason: 'prompt_input_exit', sessionId: 'sess-1', resume: { id: 'sess-1' } })
  // Past the wait a /clear allows for the session id to move on.
  await w.clock.advance(10_000)
  await w.clock.settle()
  expect(w.store.get('pins')).toEqual(before)
})

test('session mode: one character from the start, no votes, no odds, Reroll changes it', async ($, on) => {
  const w = world($, on, 'session')
  await start($, w)
  const band = await $.ui.mount(BAND)
  const named = (await band.find({ type: 'Text', text: /«/ }))?.text ?? ''
  const first = /«([^»]+)»/.exec(named)?.[1]
  expect(first).toBeDefined()

  await submit($, w, 'first request')
  await submit($, w, 'second request')
  const openers = w.asks.filter(a => a.includes('OPENER'))
  expect(openers).toHaveLength(2)
  for (const a of openers) expect(a).toContain(`Character: ${first} (`)
  // No --votes roll at all, so nothing reaches the roll log.
  expect(w.rolls.filter(r => !r.includes('--roster'))).toEqual([])
  const row = await opener($, 'second request')
  expect(await row.findAll({ type: 'Link' })).toHaveLength(0)
  expect(await row.find({ type: 'Text', text: /%/ })).toBe(undefined)
  await row.unmount()

  await band.press({ key: 'rp-reroll' })
  await w.clock.settle()
  const again = (await band.find({ type: 'Text', text: /«/ }))?.text ?? ''
  expect(/«([^»]+)»/.exec(again)?.[1]).not.toBe(first)
  await band.unmount()
})

test('Pick opens a searchable list, and a row sets the session character', async ($, on) => {
  const w = world($, on)
  await start($, w)
  await run($, 'pick')
  expect(w.panes).toEqual(['roleplay-pick'])

  const pane = await $.ui.mount(PANE)
  expect(await pane.findAll({ type: 'Button' })).toHaveLength(3)
  // Enter on an empty field picks nothing.
  await pane.input({ key: 'rp-filter', text: '' })
  expect(w.panes).toEqual(['roleplay-pick'])
  await pane.input({ key: 'rp-filter', text: 'wolf', kind: 'change' })
  // "wolf" is in Holo's traits only, which the search does not read.
  expect(await pane.findAll({ type: 'Button' })).toHaveLength(0)
  await pane.input({ key: 'rp-filter', text: 'holo', kind: 'change' })
  const rows = await pane.findAll({ type: 'Button' })
  expect(rows).toHaveLength(1)
  // Both odds, as a bookend shows them: the character's, then the universe's.
  expect(rows[0]?.text).toMatch(/Holo 2%.*FAVORITES.*25%/)
  await pane.press({ key: 'rp-c:FAVORITES|Holo' })
  await pane.unmount()
  expect(w.panes).toEqual([])

  const band = await $.ui.mount(BAND)
  expect((await band.find({ type: 'Text', text: /«/ }))?.text).toContain('«Holo» 🐺 FAVORITES')
  await band.unmount()
  await submit($, w, 'a request after the pick')
  expect(w.asks.find(a => a.includes('OPENER'))).toContain('Character: Holo (FAVORITES)')
})

test('/roleplay random leaves session mode, and its odds come back', async ($, on) => {
  const w = world($, on, 'session')
  await start($, w)
  await run($, 'random')
  await submit($, w, 'back to random please')
  const ui = await opener($, 'back to random please')
  expect(await ui.findAll({ type: 'Link' })).toHaveLength(4)
  expect((await ui.find({ type: 'Text', text: '1.2% ' }))?.text).toBe('1.2% ')
  await ui.unmount()
  expect(w.toasts.some(t => t.startsWith('🎭 Random mode'))).toBe(true)
})
