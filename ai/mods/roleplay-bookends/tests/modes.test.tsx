// Tests for the two modes (/roleplay session|random), the Reroll and Pick
// controls above the prompt, the Pick pane, and the odds drawn in random
// mode. As in flow.test.tsx, the hooks below answer for the engine: nothing
// runs a process or a model.
import { expect, test } from 'claude-code/testing'
import type { Engine } from 'claude-code/testing'
import type { On } from 'claude-code'

import { SYS, matchUniverses, matches, nextVote, parseRoster, pct, pickChar, pickUniverse, titleCase } from '../hooks/register'
import { ROLL, start, world as baseWorld } from './world'
import type { World as BaseWorld } from './world'

// What `roleplay-roll --roster` prints for a three-character cast.
const ROSTER = [
  ['GHOST IN THE SHELL', 'Togusa', '🔍', 'Methodical · earnest', '', '0.085106', '0.012158'],
  ['WARHAMMER 40K', 'Commissar', '💀', 'Stern', "'For the Emperor!'", '0.085106', '0.014184'],
  ['FAVORITES', 'Holo', '🐺', 'Wise wolf', '', '0.250000', '0.020000'],
].map(r => r.join('\t')).join('\n') + '\n'

type World = BaseWorld & {
  // Each roleplay-roll command line, and how many --roster runs fail before
  // one answers.
  rolls: string[]; rosterFails: number
  // Each vote's process.run argv, and how many vote runs fail next.
  voteRuns: string[][]; voteFails: number
  // What --roster prints, and a universe whose rolls print nothing (nobody
  // in it can roll), as the script does.
  roster: string; deadUniverse: string
}

// The shared engine (./world), with the roster, the roll log and vote runs
// that can fail. Every prompt starts a turn (the shared default).
function world($: Engine, on: On, saved?: string): World {
  const w: World = Object.assign(baseWorld($, on, { run: argv => runFor(w, argv) }), {
    rolls: [], rosterFails: 0, voteRuns: [], voteFails: 0, roster: ROSTER, deadUniverse: '',
  })
  if (saved) w.store.set('mode', saved)
  return w
}

function runFor(w: World, argv: readonly string[]) {
  const cmd = argv.join(' ')
  if (argv[2]?.includes('votes.lock')) {
    w.voteRuns.push([...argv])
    if (w.voteFails > 0) {
      w.voteFails--
      return { exitCode: 1, stderr: 'disk full' }
    }
  }
  if (cmd.includes('roleplay-roll')) w.rolls.push(cmd)
  if (cmd.includes('--roster') && w.rosterFails > 0) {
    w.rosterFails--
    throw new Error('timed out')
  }
  if (w.deadUniverse && argv.includes(`--universe=${w.deadUniverse}`)) return { stdout: '' }
  return { stdout: cmd.includes('--roster') ? w.roster : cmd.includes('roleplay-roll') ? ROLL : '' }
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

// The vote buttons a drawn bookend holds (keys rv-<id>-<slot>).
async function voteButtons(ui: { findAll: (q: { type: 'Button' }) => Promise<readonly { key?: string }[]> }) {
  return (await ui.findAll({ type: 'Button' })).filter(b => b.key?.startsWith('rv-'))
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
  // Halves round up, as roleplay-say's awk does.
  expect(pct(0.125)).toBe('13%')
  expect(pct(0.0625)).toBe('6.3%')
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
  expect(await voteButtons(ui)).toHaveLength(4)
  await ui.unmount()
  expect(w.rolls.some(r => r.includes('--votes'))).toBe(true)
  // The row above the prompt is always there: mode button and Pick, no Reroll.
  const band = await $.ui.mount(BAND)
  expect((await band.findAll({ type: 'Button' })).map(b => b.text)).toEqual(['random'])
  expect((await band.find({ type: 'Text', text: /new character each prompt/ }))?.text).toBe('a new character each prompt')
  await band.unmount()
})

test('the mode button cycles random, session, universe; saves the default; shows Reroll outside random', async ($, on) => {
  const w = world($, on)
  await start($, w)
  expect(w.registered).toEqual([{ name: 'roleplay', immediate: true }])
  const band = await $.ui.mount(BAND)
  await band.press({ key: 'rp-mode' })
  await w.clock.settle()
  expect(w.store.get('mode')).toBe('session')
  expect((await band.findAll({ type: 'Button' })).map(b => b.text)).toEqual(['session', 'Reroll', 'Pick'])
  const named = (await band.find({ type: 'Text', text: /«/ }))?.text ?? ''
  const who = parseRoster(ROSTER).find(c => named.startsWith(`«${c.name}»`))!
  expect(who).toBeDefined()
  // From session mode, the button carries the character's universe over.
  await band.press({ key: 'rp-mode' })
  await w.clock.settle()
  expect(w.store.get('mode')).toBe('universe')
  expect((await band.findAll({ type: 'Button' })).map(b => b.text)).toEqual(['universe', 'Reroll', 'Pick'])
  expect((await band.find({ type: 'Text', text: /from / }))?.text).toBe(`a new character each prompt from ${titleCase(who.universe)}`)
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

test('a vote button casts, a second press clears, the other button changes it', async ($, on) => {
  const w = world($, on)
  const runs = w.voteRuns
  await start($, w)
  await submit($, w, 'please vote on this')
  const ui = await opener($, 'please vote on this')
  const args = (i: number) => runs[i]!.slice(4)
  const colored = async (key: string) => (await ui.find({ key }))?.children?.[0]
  // Slot 2: opener, character, down. Cast.
  await ui.press({ key: 'rv-ab12-2' })
  expect(args(0)).toEqual(['ab12', 'opener', 'down', 'character', 'Togusa'])
  expect(w.toasts.at(-1)).toBe('− Togusa')
  expect((await ui.find({ key: 'rv-ab12-2' }))?.props).toMatchObject({ dimColor: false })
  expect(await colored('rv-ab12-2')).toMatchObject({ type: 'Text', props: { bold: true, color: 'error' } })
  expect((await ui.find({ key: 'rv-ab12-1' }))?.props).toMatchObject({ dimColor: true })
  // Slot 1, the other way on the same part: change.
  await ui.press({ key: 'rv-ab12-1' })
  expect(args(1)).toEqual(['ab12', 'opener', 'up', 'character', 'Togusa'])
  expect(await colored('rv-ab12-1')).toMatchObject({ props: { color: 'success' } })
  expect((await ui.find({ key: 'rv-ab12-2' }))?.props).toMatchObject({ dimColor: true })
  // The same button again: clear (an empty vote).
  await ui.press({ key: 'rv-ab12-1' })
  expect(args(2)).toEqual(['ab12', 'opener', '', 'character', 'Togusa'])
  expect(w.toasts.at(-1)).toBe('Vote cleared: Togusa')
  expect((await ui.find({ key: 'rv-ab12-1' }))?.props).toMatchObject({ dimColor: true })
  // The universe is a part of its own.
  await ui.press({ key: 'rv-ab12-3' })
  expect(args(3)).toEqual(['ab12', 'opener', 'up', 'universe', 'GHOST IN THE SHELL'])
  await ui.unmount()
})

test('two quick presses on one button cast and then clear, in order', async ($, on) => {
  const w = world($, on)
  await start($, w)
  await submit($, w, 'two quick presses')
  const ui = await opener($, 'two quick presses')
  await Promise.all([ui.press({ key: 'rv-ab12-1' }), ui.press({ key: 'rv-ab12-1' })])
  expect(w.voteRuns.map(r => r[6])).toEqual(['up', ''])
  expect((await ui.find({ key: 'rv-ab12-1' }))?.props).toMatchObject({ dimColor: true })
  await ui.unmount()
})

test('a vote that fails to save changes nothing on screen', async ($, on) => {
  const w = world($, on)
  await start($, w)
  await submit($, w, 'a vote on a full disk')
  const ui = await opener($, 'a vote on a full disk')
  w.voteFails = 1
  await ui.press({ key: 'rv-ab12-1' })
  expect(w.toasts.at(-1)).toBe('Vote not saved: Error: disk full')
  expect((await ui.find({ key: 'rv-ab12-1' }))?.props).toMatchObject({ dimColor: true })
  // The next press still casts: the failed one left no vote behind.
  await ui.press({ key: 'rv-ab12-1' })
  expect(w.voteRuns.at(-1)!.slice(4)).toEqual(['ab12', 'opener', 'up', 'character', 'Togusa'])
  await ui.unmount()
})

test('a press cycle: none, cast, cleared, and the other way changes', () => {
  expect(nextVote(undefined, 'up')).toBe('up')
  expect(nextVote('up', 'up')).toBe(undefined)
  expect(nextVote('up', 'down')).toBe('down')
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
  expect(await voteButtons(row)).toHaveLength(0)
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
  expect(await voteButtons(ui)).toHaveLength(4)
  expect((await ui.find({ type: 'Text', text: '1.2% ' }))?.text).toBe('1.2% ')
  await ui.unmount()
  expect(w.toasts.some(t => t.startsWith('🎭 Random mode'))).toBe(true)
})

test('a weighted universe pick follows the universe shares and can skip one', () => {
  const all = parseRoster(ROSTER)
  // Shares 0.085, 0.085, 0.25 of 0.42: GHOST first, FAVORITES the last 60%.
  expect(pickUniverse(all, 0)).toBe('GHOST IN THE SHELL')
  expect(pickUniverse(all, 0.3)).toBe('WARHAMMER 40K')
  expect(pickUniverse(all, 0.9)).toBe('FAVORITES')
  expect(pickUniverse(all, 0, 'GHOST IN THE SHELL')).toBe('WARHAMMER 40K')
  expect(pickUniverse([], 0.5)).toBe(null)
  expect(matchUniverses(all, 'ghost').map(x => x.name)).toEqual(['GHOST IN THE SHELL'])
})

const GHOST_PIN = { 'sess-1': { mode: 'universe', who: null, universe: 'GHOST IN THE SHELL' } }

test('universe mode rolls inside the pinned universe, never the same character twice running', async ($, on) => {
  const w = world($, on, 'universe')
  w.store.set('pins', GHOST_PIN)
  await start($, w)
  const band = await $.ui.mount(BAND)
  expect((await band.find({ type: 'Text', text: /from / }))?.text).toBe('a new character each prompt from Ghost in the Shell')
  await band.unmount()
  await submit($, w, 'first universe request')
  await submit($, w, 'second universe request')
  const rolls = w.rolls.filter(r => r.includes('--votes'))
  expect(rolls).toHaveLength(2)
  for (const r of rolls) expect(r).toContain('--universe=GHOST IN THE SHELL')
  expect(rolls[0]).not.toContain('--not=')
  expect(rolls[1]).toContain('--not=Togusa')
  // Votes as in random mode; the character's odds are its share of the universe.
  const ui = await opener($, 'second universe request')
  expect(await voteButtons(ui)).toHaveLength(4)
  expect((await ui.find({ type: 'Text', text: '14% ' }))?.text).toBe('14% ')
  expect((await ui.find({ type: 'Text', text: '8.5% ' }))?.text).toBe('8.5% ')
  await ui.unmount()
})

test('universe mode: Reroll changes the universe and keeps the mode', async ($, on) => {
  const w = world($, on, 'universe')
  w.store.set('pins', GHOST_PIN)
  await start($, w)
  const band = await $.ui.mount(BAND)
  await band.press({ key: 'rp-reroll' })
  await w.clock.settle()
  const pins = w.store.get('pins') as Record<string, { mode: string; universe: string }>
  expect(pins['sess-1']?.mode).toBe('universe')
  expect(pins['sess-1']?.universe).not.toBe('GHOST IN THE SHELL')
  expect(w.toasts.at(-1)).toMatch(/^🎭 This session's universe: /)
  await band.unmount()
})

test('universe mode: Pick lists universes, and a row sets the session universe', async ($, on) => {
  const w = world($, on, 'universe')
  w.store.set('pins', GHOST_PIN)
  await start($, w)
  await run($, 'pick')
  const pane = await $.ui.mount(PANE)
  const rows = await pane.findAll({ type: 'Button' })
  expect(rows).toHaveLength(3)
  expect(rows[0]?.text).toMatch(/Ghost in the Shell 8.5% · 1 character · now/)
  await pane.input({ key: 'rp-filter', text: 'warham' })
  await pane.unmount()
  expect(w.panes).toEqual([])
  const pins = w.store.get('pins') as Record<string, { mode: string; universe: string }>
  expect(pins['sess-1']).toMatchObject({ mode: 'universe', universe: 'WARHAMMER 40K' })
  await submit($, w, 'a request after the universe pick')
  expect(w.rolls.at(-1)).toContain('--universe=WARHAMMER 40K')
})

test('a pinned universe that left the roster is replaced', async ($, on) => {
  const w = world($, on, 'universe')
  w.store.set('pins', { 'sess-1': { mode: 'universe', who: null, universe: 'GONE' } })
  await start($, w)
  const pins = w.store.get('pins') as Record<string, { universe: string }>
  expect(['GHOST IN THE SHELL', 'WARHAMMER 40K', 'FAVORITES']).toContain(pins['sess-1']?.universe)
})

test('/clear gives a universe-mode session a new universe pin under the new id', async ($, on) => {
  const w = world($, on, 'universe')
  w.store.set('pins', GHOST_PIN)
  await start($, w)
  w.sid = 'sess-2'
  await $.session.end({ reason: 'clear', sessionId: 'sess-1', resume: { id: 'sess-1' } })
  await w.clock.settle()
  const pins = w.store.get('pins') as Record<string, { mode: string; universe: string | null }>
  expect(pins['sess-2']?.mode).toBe('universe')
  expect(pins['sess-2']?.universe).toBeTruthy()
  expect(pins['sess-1']?.universe).toBe('GHOST IN THE SHELL')
})

test('/roleplay universe from random mode rolls a universe and says so', async ($, on) => {
  const w = world($, on)
  await start($, w)
  await run($, 'universe')
  expect(w.store.get('mode')).toBe('universe')
  expect(w.toasts.at(-1)).toMatch(/^🎭 Universe mode: a new character on each prompt, from /)
})

test('session mode into universe mode keeps the character\'s universe, and the first roll skips that character', async ($, on) => {
  const w = world($, on, 'session')
  const holo = parseRoster(ROSTER)[2]!
  w.store.set('pins', { 'sess-1': { mode: 'session', who: holo } })
  await start($, w)
  await run($, 'universe')
  expect(w.toasts.at(-1)).toBe('🎭 Universe mode: a new character on each prompt, from Favorites. New sessions start this way too.')
  await submit($, w, 'first prompt in the universe')
  const roll = w.rolls.filter(r => r.includes('--votes')).at(-1)
  expect(roll).toContain('--universe=FAVORITES')
  expect(roll).toContain('--not=Holo')
})

test('a pinned universe nobody can roll: this turn gets a random roll, and the session another universe', async ($, on) => {
  const w = world($, on, 'universe')
  w.store.set('pins', GHOST_PIN)
  w.deadUniverse = 'GHOST IN THE SHELL'
  await start($, w)
  await submit($, w, 'a prompt in a dead universe')
  // The fallback roll still writes a bookend, with random mode's odds.
  expect(w.asks.find(a => a.includes('OPENER'))).toContain('Character: Togusa')
  const ui = await opener($, 'a prompt in a dead universe')
  expect((await ui.find({ type: 'Text', text: '1.2% ' }))?.text).toBe('1.2% ')
  await ui.unmount()
  const pins = w.store.get('pins') as Record<string, { mode: string; universe: string }>
  expect(pins['sess-1']?.mode).toBe('universe')
  expect(pins['sess-1']?.universe).not.toBe('GHOST IN THE SHELL')
  expect(w.toasts.at(-1)).toMatch(/^🎭 Nobody in Ghost in the Shell can roll\. This session's universe: /)
  // The roster was read again, in case it changed.
  expect(w.rolls.filter(r => r.includes('--roster')).length).toBeGreaterThanOrEqual(2)
})

test('Pick does not list a universe that cannot roll', async ($, on) => {
  const w = world($, on, 'universe')
  w.roster = ROSTER + ['BENCHED', 'Nobody', '🪑', 'Off', '', '0.000000', '0.000000'].join('\t') + '\n'
  w.store.set('pins', GHOST_PIN)
  await start($, w)
  await run($, 'pick')
  const pane = await $.ui.mount(PANE)
  expect(await pane.findAll({ type: 'Button' })).toHaveLength(3)
  expect(await pane.find({ type: 'Button', text: /Benched/ })).toBe(undefined)
  await pane.unmount()
})

test('picking the universe already pinned keeps skipping the last character', async ($, on) => {
  const w = world($, on, 'universe')
  w.store.set('pins', GHOST_PIN)
  await start($, w)
  await submit($, w, 'a prompt before the re-pick')
  await run($, 'pick')
  const pane = await $.ui.mount(PANE)
  await pane.press({ key: 'rp-u:GHOST IN THE SHELL' })
  await pane.unmount()
  await submit($, w, 'a prompt after the re-pick')
  expect(w.rolls.at(-1)).toContain('--not=Togusa')
})

test('the writer is told who did the work: the assistant, not the user or the character', () => {
  expect(SYS).toContain('There are three parties.')
  expect(SYS).toContain('Never say "you" or "I" for something the assistant did')
})
