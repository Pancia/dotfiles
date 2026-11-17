// The bookend layout: a dim credit row (🎭 name · emoji Universe), the quote
// on rows of its own, and the odds and vote buttons on a last row. Each row is
// wrapped by hand to the viewport, so no row is wider than it: on 2026-11-17
// a long name and universe in one flex row wrapped each in its own column.
import { expect, test } from 'claude-code/testing'
import type { Engine } from 'claude-code/testing'
import type { On } from 'claude-code'

import { titleCase } from '../hooks/register'
import { start, world } from './world'

const NAME = 'Julia Sugarbaker (Designing Women)'
const TAG = `[🎭 Character Roll: «${NAME}» 🏛 STEEL MAGNOLIAS — Grand · withering || vote id: cd34]`
const LINE = 'Acceptable, she says. Very well, darling; I shall commit it properly, with the 12 November edits included and every last one accounted for.'

async function closer($: Engine, on: On, columns: number) {
  const w = world($, on, {
    run: argv => ({
      stdout: argv.join(' ').includes('roleplay-roll')
        ? JSON.stringify({ hookSpecificOutput: { hookEventName: 'UserPromptSubmit', additionalContext: TAG } })
        : '',
    }),
    answer: () => LINE,
  })
  await start($, w)
  await $.prompt.submit({ text: 'commit it', origin: { kind: 'composer' }, wait: false })
  await w.clock.settle()
  const answer = 'Committed.'
  await $.turn.complete({ answer, durationMs: 10, isAborted: false, turnId: 't-9', reason: 'answer' })
  await w.clock.settle()
  return $.ui.mount({
    plugin: 'roleplay-bookends',
    surface: 'terminal',
    component: 'AssistantMessage',
    viewport: { columns, rows: 40, isPaneDocked: false },
    props: { text: answer, isFirstOfReply: true },
  } as Parameters<Engine['ui']['mount']>[0])
}

// Display cells, as the mod counts them (wide emoji are 2).
const cells = (t: string) => [...t].reduce((n, ch) => {
  const c = ch.codePointAt(0)!
  if (c === 0x200d || (c >= 0xfe00 && c <= 0xfe0f)) return n
  return n + (c >= 0x1f000 || (c >= 0x2600 && c <= 0x27bf) ? 2 : 1)
}, 0)

test('a long name and universe get a credit row of their own, and the quote follows', async ($, on) => {
  const ui = await closer($, on, 60)
  const texts = (await ui.findAll({ type: 'Text' })).map(t => t.text).filter(t => t !== '▎ ')
  // Too long for one row: the name and the universe each start their own.
  expect(texts[0]).toBe('🎭 Julia Sugarbaker (Designing Women)')
  expect(texts[1]).toBe('🏛 Steel Magnolias')
  expect(texts.join(' ')).not.toContain('«')
  // Every hand-wrapped row fits in 60 columns less the indent, bar and margin.
  const width = 60 - 2 - 2 - 2
  for (const t of texts) expect(cells(t)).toBeLessThanOrEqual(width)
  // The quote starts its own row, not the end of the credit row.
  expect(texts.some(t => t.startsWith('"Acceptable,'))).toBe(true)
  // The buttons still draw, on the row after the quote.
  expect((await ui.findAll({ type: 'Button' })).filter(b => b.key?.startsWith('rv-cd34-'))).toHaveLength(4)
  await ui.unmount()
})

test('a credit that fits stays on one row', async ($, on) => {
  const ui = await closer($, on, 120)
  const texts = (await ui.findAll({ type: 'Text' })).map(t => t.text)
  expect(texts).toContain('🎭 Julia Sugarbaker (Designing Women) · 🏛 Steel Magnolias')
  await ui.unmount()
})

test('universes in capitals read in title case, digits kept', () => {
  expect(titleCase('GHOST IN THE SHELL')).toBe('Ghost in the Shell')
  expect(titleCase('THE LEGEND OF ZELDA')).toBe('The Legend of Zelda')
  expect(titleCase('WARHAMMER 40K')).toBe('Warhammer 40K')
  expect(titleCase('Already Mixed')).toBe('Already Mixed')
})
