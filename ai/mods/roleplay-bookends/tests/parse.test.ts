// parseWho on the tags `roleplay-roll --votes` prints. The fixtures follow
// its printf lines (roleplay/bin/roleplay-roll): the tag, the two signature
// forms (each with a second " — "), the vote id, and the JSON escape of the
// hook envelope. The traits and signature are the Malfoid row of
// roleplay/roster.tsv, which has double quotes and an apostrophe.
import { expect, test } from 'claude-code/testing'

import { parseWho } from '../hooks/register'

const TRAITS = 'Grown-up Malfoid, now your wife (Harry Potter) · calls you "darling" with a sneer and means it fondly'
const SIG = "'You're a Malfoy now. Act like it.'"
const UNLOCKED = `SIGNATURE LINE UNLOCKED (1/3 roll) — you may use: ${SIG}`
const SPENT = `signature line spent this roll — do not use ${SIG}; reach for a less-worn part of the character instead`

// The tag as the mod reads it: out of the hook's JSON envelope.
function tagOf(line: string): string {
  const envelope = JSON.stringify({
    hookSpecificOutput: { hookEventName: 'UserPromptSubmit', additionalContext: `[🎭 Character Roll: ${line}]` },
  })
  return JSON.parse(envelope).hookSpecificOutput.additionalContext
}

test('an unlocked signature, quotes in the traits and a vote id', () => {
  const w = parseWho(tagOf(`«Malfoid (Wife)» 💍 FAVORITES — ${TRAITS} || ${UNLOCKED} || vote id: k3x9`))
  expect(w).toEqual({
    name: 'Malfoid (Wife)',
    emoji: '💍',
    universe: 'FAVORITES',
    traits: TRAITS,
    extra: UNLOCKED,
    voteId: 'k3x9',
  })
})

test('a spent signature and a universe of several words', () => {
  const w = parseWho(tagOf(`«Togusa» 🔍 GHOST IN THE SHELL — Methodical · earnest || ${SPENT} || vote id: 0a1b`))
  expect(w?.name).toBe('Togusa')
  expect(w?.universe).toBe('GHOST IN THE SHELL')
  expect(w?.traits).toBe('Methodical · earnest')
  expect(w?.extra).toBe(SPENT)
  expect(w?.voteId).toBe('0a1b')
})

test('no vote id when the roll log could not be written', () => {
  const w = parseWho(tagOf(`«Malfoid (Wife)» 💍 FAVORITES — ${TRAITS} || ${SPENT}`))
  expect(w?.voteId).toBeUndefined()
  expect(w?.extra).toBe(SPENT)
})

test('no signature and no vote id', () => {
  const w = parseWho(tagOf('«Togusa» 🔍 GHOST IN THE SHELL — Methodical · earnest'))
  expect(w?.traits).toBe('Methodical · earnest')
  expect(w?.extra).toBe('')
  expect(w?.voteId).toBeUndefined()
})

test('text with no roll tag gives null', () => {
  expect(parseWho('no tag here')).toBeNull()
})
