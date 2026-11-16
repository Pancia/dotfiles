// Row keys and pruning: withRow keeps the newest KEEP (40) rows per map.
import { expect, test } from 'claude-code/testing'

import { headKey, withRow } from '../hooks/register'
import type { Line } from '../types'

const LINE: Line = { name: 'Togusa', emoji: '🔍', universe: 'GHOST IN THE SHELL', text: 'a line', ms: 0 }

test('a prompt "2", the newest of 41 rows, keeps its row', () => {
  // Review 2, finding 4: JavaScript lists integer-like keys ("2") first, so
  // without the "h:" prefix withRow pruned the newest row as the oldest.
  let m: Record<string, Line> = {}
  for (let i = 0; i < 40; i++) m = withRow(m, headKey('p' + i), LINE)
  m = withRow(m, headKey('2'), LINE)
  expect(Object.keys(m)).toContain(headKey('2'))
  expect(Object.keys(m)).not.toContain(headKey('p0'))
  expect(Object.keys(m)).toHaveLength(40)
})

test('setting a row again moves it to the newest place', () => {
  let m: Record<string, Line> = {}
  m = withRow(m, headKey('first'), LINE)
  for (let i = 0; i < 39; i++) m = withRow(m, headKey('p' + i), LINE)
  m = withRow(m, headKey('first'), LINE)
  m = withRow(m, headKey('one more'), LINE)
  expect(Object.keys(m)).toContain(headKey('first'))
  expect(Object.keys(m)).not.toContain(headKey('p0'))
})
