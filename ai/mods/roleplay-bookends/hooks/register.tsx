// roleplay-bookends — a side model (MODEL, Sonnet) writes the roleplay
// bookends outside the main model:
//   * opener: started when the turn of a typed prompt starts (not when a
//     prompt is queued), from the prompt and the end of the previous answer,
//     drawn under the user's message as soon as it arrives;
//   * closer: started when that turn ends, from the prompt and the final
//     answer, drawn under the final answer's last block.
// Display only: nothing is added to the transcript, so the main model never
// sees these lines. Each line is appended to
// ~/.local/state/roleplay/mod-lines.jsonl with its session, turn and vote id;
// a vote (castVote, the same line lib/lua/seeds/rolevote.lua writes for the
// old hammerspoon:// links) records only the vote id, place and kind, so that
// log is where a voted line is found again.
//
// Review: .cc/reports/REVIEW-roleplay-bookends-mod.md (2026-11-15).
import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'

import type { Char, Kind, Line, Mode, Odds, Pin, VoteCount, Way } from '../types'

const openers = atom({ plugin: 'roleplay-bookends', key: 'openers' } as const, {} as Record<string, Line>)
const closers = atom({ plugin: 'roleplay-bookends', key: 'closers' } as const, {} as Record<string, Line>)
const votes = atom({ plugin: 'roleplay-bookends', key: 'votes' } as const, { waiting: 0, old: 0 } as VoteCount)
// Three modes, set by /roleplay random|universe|session. The saved default
// ($.store 'mode') is read once per session; a reload keeps the session's.
// In session mode one character writes every bookend, the vote links do not
// show, and a row above the prompt names the character with Reroll and Pick.
// In random mode each bookend shows its character's and universe's odds.
// Universe mode pins one universe for the session and rolls a new character
// from it on each prompt (never the previous one twice in a row, except
// after a mod reload, which forgets the previous one), with odds and vote
// links as in random mode; Reroll and Pick change the universe.
const pin = atom({ plugin: 'roleplay-bookends', key: 'pin' } as const, { mode: null, who: null } as Pin)
// The Pick pane's search text.
const filter = atom({ plugin: 'roleplay-bookends', key: 'filter' } as const, '')
const PICK = 'roleplay-pick'
// The vote standing on each bookend part, from this session's buttons, by
// `${voteId}:${place}:${kind}` (kind: character or universe). Drawn in the
// vote's color; a press of the same button clears it, of the other changes it.
const myVotes = atom({ plugin: 'roleplay-bookends', key: 'myVotes' } as const, {} as Record<string, Way>)

// Vote reminder: a row above the prompt when more than VOTES_OLD votes have
// waited a week or more, or more than VOTES_MANY are waiting. Its button
// opens a review session in a new iTerm tab (bin/rolevotes-review). The
// review writes votes-reviewed-at, which resets the count.
const VOTES_OLD = 3
const VOTES_MANY = 12
const WEEK_MS = 7 * 24 * 3600 * 1000
// Show the row whatever the count, to try the button.
const VOTES_DEMO = false

const MODEL = 'sonnet'
// The "(sonnet opener 1.2s)" note after each line: side-by-side testing only.
const SHOW_TIMING = false
// True while the roleplay-roll UserPromptSubmit hook is still registered:
// take its roll from rolls.tsv so both voices play the same character.
// False once the hook is gone: the mod rolls for itself.
const HOOK_ROLLS = false
// Write each step to mod-debug.log.
const DEBUG = true
// Rows kept per map; older ones lose their bookend row.
const KEEP = 40

// The "three parties" sentences stop a line from crediting or blaming the
// user for what the assistant did: the old prompt gave "you admitted you'd
// looked in the wrong folder" for a reply where the assistant admitted it,
// 6 times in 8 on that reply; this one 0 in 10 (2026-11-17,
// .cc/reports/REPORT-roleplay-who-did-what.md).
export const SYS =
  "You write one short in-character line for a character who bookends an AI coding assistant's replies to its user, " +
  'and speaks to the user. There are three parties. The user wrote only their request. ' +
  'The assistant did the work and wrote the reply, so in the reply "I" and "we" mean the assistant and "you" means the user. ' +
  'The character is neither: it watches and comments. ' +
  'Never say "you" or "I" for something the assistant did, found, said or admitted; if the line mentions it, the assistant did it. ' +
  "At most 25 words, in the character's own voice, about this specific work. " +
  'A plain status sentence with no character in it is a failure. ' +
  "Do not use jargon from the character's universe to describe the technical work. " +
  'Never repeat the example lines. Output only the line itself: no quotes, no name, no preamble.'

type Who = { name: string; emoji: string; universe: string; traits: string; extra: string; voteId?: string; odds?: Odds }

// One turn that got an opener: what its closer needs.
type Turn = { roll: Promise<Who | null>; prompt: string }

// [🎭 Character Roll: «Name» 🥷 UNIVERSE — traits || extra || vote id: x]
const WHO = /«([^»]+)»\s*(\S+)\s+(.+?)\s+—\s+([^|\]\n]+)((?:\|\|[^\]\n]*)?)/

export function parseWho(s: string): Who | null {
  const m = WHO.exec(s)
  if (!m) return null
  const parts = (m[5] ?? '').split('||').map(x => x.trim())
  const voteId = parts.map(x => /^vote id: (\w+)$/.exec(x)?.[1]).find(Boolean)
  const extra = parts.filter(x => x && !x.startsWith('vote id')).join(' ')
  return { name: m[1]!.trim(), emoji: m[2]!, universe: m[3]!.trim(), traits: m[4]!.trim(), extra, ...(voteId ? { voteId } : {}) }
}

// `roleplay-roll --roster`: one tab-separated row per character. Anything
// else (an old script, a failed run) gives no rows, and then no odds show and
// session mode rolls through the script instead.
export function parseRoster(s: string): Char[] {
  const out: Char[] = []
  for (const row of s.split('\n')) {
    const f = row.split('\t')
    if (f.length !== 7) continue
    const u = Number(f[5])
    const c = Number(f[6])
    if (!f[0] || !f[1] || Number.isNaN(u) || Number.isNaN(c)) continue
    out.push({ universe: f[0], name: f[1], emoji: f[2]!, traits: f[3]!, sig: f[4]!, u, c })
  }
  return out
}

// A share as a short percent: 8.5%, 1.4%, 0.18%, 12%.
// Halves round up, as roleplay-say's awk rounds them: 12.5% is 13%.
export function pct(x: number): string {
  const p = x * 100
  const at = (d: number) => (Math.floor(p * 10 ** d + 0.5) / 10 ** d).toFixed(d)
  const s = p >= 10 ? at(0) : p >= 1 ? at(1) : at(2)
  return `${s.replace(/\.0+$/, '')}%`
}

// Characters whose name or universe holds every word of the search.
export function matches(all: readonly Char[], q: string): Char[] {
  const words = q.toLowerCase().split(/\s+/).filter(Boolean)
  return all.filter(c => {
    const hay = `${c.name} ${c.universe}`.toLowerCase()
    return words.every(w => hay.includes(w))
  })
}

// The mode button's order. Session comes before universe, so a press from
// session mode carries the session character's universe over (setMode).
export const MODES: readonly Mode[] = ['random', 'session', 'universe']
export function isMode(x: unknown): x is Mode {
  return typeof x === 'string' && (MODES as readonly string[]).includes(x)
}

// Each universe once, in roster order, with its share of rolls and members.
export type Universe = { name: string; u: number; members: number }
export function universes(all: readonly Char[]): Universe[] {
  const out = new Map<string, Universe>()
  for (const c of all) {
    const x = out.get(c.universe)
    if (x) x.members++
    else out.set(c.universe, { name: c.universe, u: c.u, members: 1 })
  }
  return [...out.values()]
}

// A weighted pick of a universe by its share of rolls, as the script's stage
// 1. A universe with share 0 never rolls, and Pick does not list it: the
// roster cannot tell a benched universe from one whose members are all off,
// and a pinned universe nobody can roll gives no bookend.
export function pickUniverse(all: readonly Char[], r: number, not?: string): string | null {
  const pool = universes(all).filter(x => x.u > 0 && x.name !== not)
  const sum = pool.reduce((n, x) => n + x.u, 0)
  if (!pool.length || sum <= 0) return null
  let at = r * sum
  for (const x of pool) {
    at -= x.u
    if (at < 0) return x.name
  }
  return pool[pool.length - 1]!.name
}

// A weighted pick by overall share, which is the script's two-stage roll.
// `not` names a character to skip (Reroll never gives the same one back).
export function pickChar(all: readonly Char[], r: number, not?: string): Char | null {
  const pool = all.filter(c => c.c > 0 && c.name !== not)
  const sum = pool.reduce((n, c) => n + c.c, 0)
  if (!pool.length || sum <= 0) return null
  let at = r * sum
  for (const c of pool) {
    at -= c.c
    if (at < 0) return c
  }
  return pool[pool.length - 1]!
}

function norm(s: string): string {
  return s.replace(/\s+/g, ' ').trim()
}

// Opener rows are found by the prompt's start; closer rows by the answer's
// end, which is the end of its last text block, where the closer belongs.
// The "h:"/"t:" prefix keeps a prompt like "2" from being an integer-like key,
// which JavaScript orders first and withRow would then prune at once.
export function headKey(s: string): string {
  return 'h:' + norm(s).slice(0, 200)
}
function tailKey(s: string): string {
  return 't:' + norm(s).slice(-200)
}

// Lines in a prompt as sent, for weighing a paste row's "+N lines".
function lineCount(s: string): number {
  return s.split('\n').length
}

// The row shows a paste as "[Pasted text #1 +14 lines]" (or an image as
// "[Image #1]") while the prompt holds the pasted text, so the head key can
// miss. Then the row matches a stored prompt holding each typed piece around
// the placeholders, in order, starting with the first and ending with the
// last, with at least as many lines as the placeholders say were pasted.
// Of several matches, the one closest in line count wins. The full prompts
// live in a module map, not in the drawn state, so a redraw copies none.
const PLACEHOLDER = /\[(?:Pasted text|Image) #\d+[^\]]*\]/
function findOpener(m: Record<string, Line>, shown: string): Line | undefined {
  const exact = m[headKey(shown)]
  if (exact || !PLACEHOLDER.test(shown)) return exact
  const parts = norm(shown).split(new RegExp(PLACEHOLDER.source, 'g')).map(p => p.trim())
  // A paste with no typed text around it matches every prompt: draw nothing
  // rather than repeat the newest opener under each such row.
  if (parts.every(p => !p)) return undefined
  const pasted = [...shown.matchAll(/\[Pasted text #\d+ \+(\d+) lines?\]/g)].reduce((n, x) => n + Number(x[1]), 0)
  const want = lineCount(shown) + pasted
  const first = parts[0] ?? ''
  const last = parts[parts.length - 1] ?? ''
  let best: { key: string; gap: number } | undefined
  for (const [key, p] of prompts) {
    const full = p.full
    if (!m[key] || p.lines < pasted || !full.startsWith(first) || !full.endsWith(last)) continue
    let at = 0
    let ok = true
    for (const piece of parts) {
      if (!piece) continue
      const i = full.indexOf(piece, at)
      if (i < 0) {
        ok = false
        break
      }
      at = i + piece.length
    }
    if (!ok) continue
    const gap = Math.abs(p.lines - want)
    if (!best || gap <= best.gap) best = { key, gap }
  }
  return best ? m[best.key] : undefined
}

// Module state: lost on a reload; reset on /clear by session.end.
let examples = ''
let lastAnswer = ''
// Typed prompts seen at submit, oldest first, waiting for their turn. One
// folded into a running turn never starts its own, so entries expire.
let queue: { text: string; at: number }[] = []
const QUEUE_MS = 10 * 60 * 1000
// Turns that got an opener, by turn id. `roll` settles once the character is
// known, so a turn that ends first still gets its closer.
const turns = new Map<string, Turn>()
// Universe mode: the last character rolled, passed as --not so the same one
// never writes two prompts in a row.
let lastInUniverse = ''
// Full prompts of opener rows, by head key, for findOpener; at most KEEP.
const prompts = new Map<string, { full: string; lines: number }>()
// Vote ids already given to a turn, so one roll is never used twice.
const usedVotes = new Set<string>()
// When the reminder's Review button last ran, to ignore a double press.
let lastReviewPress = 0
// The roster with its odds, read once per load; empty until then.
let roster: Char[] = []
let rosterLoad: Promise<void> | null = null

function resetSession() {
  lastAnswer = ''
  lastInUniverse = ''
  queue = []
  turns.clear()
  prompts.clear()
}

// The typed prompt a turn starts with: an exact match first, newest first;
// failing that, the newest entry if the turn text contains it and it is long
// enough not to be a chance substring ("y", "ok"). Expired entries drop out.
function takeQueued(turnText: string, now: number): { text: string; at: number } | undefined {
  queue = queue.filter(q => now - q.at < QUEUE_MS)
  const text = norm(turnText)
  let i = -1
  for (let j = queue.length - 1; j >= 0; j--) {
    if (norm(queue[j]!.text) === text) {
      i = j
      break
    }
  }
  if (i < 0 && queue.length) {
    const newest = norm(queue[queue.length - 1]!.text)
    if (newest.length >= 20 && text.includes(newest)) i = queue.length - 1
  }
  if (i < 0) return undefined
  const q = queue[i]!
  // Older entries never started a turn (folded into a running one): drop them.
  queue = queue.slice(i + 1)
  return q
}

function samples(name: string): string[] {
  const i = examples.indexOf(` ${name} · `)
  if (i < 0) return []
  const end = examples.indexOf('\n---', i)
  const block = examples.slice(i, end < 0 ? undefined : end)
  const out = [...block.matchAll(/— \*"(.*?)"\*/g)].map(m => m[1]!)
  for (let j = out.length - 1; j > 0; j--) {
    const k = Math.floor(Math.random() * (j + 1))
    const t = out[j]!
    out[j] = out[k]!
    out[k] = t
  }
  return out.slice(0, 2)
}

function exampleBlock(name: string): string {
  const ex = samples(name)
  return ex.length ? `Example lines in this voice (style only, do not copy):\n${ex.map(x => `- ${x}`).join('\n')}\n` : ''
}

function pendingLine(w: Who): Line {
  return {
    name: w.name, emoji: w.emoji, universe: w.universe, text: null, ms: 0,
    ...(w.voteId ? { voteId: w.voteId } : {}), ...(w.odds ? { odds: w.odds } : {}),
  }
}

// The signature line is drawn per roll at 1/3, as roleplay-roll does.
function sigNote(sig: string): string {
  if (!sig) return ''
  return Math.random() < 1 / 3
    ? `Signature line unlocked this time: you may use ${sig}.`
    : `Signature line spent this time: do not use ${sig}; use a less-worn part of the character.`
}

// A session character as one turn's roll: the signature drawn again per turn,
// so an unlocked draw does not invite the catchphrase on every line.
function whoFor(c: Char): Who {
  return { name: c.name, emoji: c.emoji, universe: c.universe, traits: c.traits, extra: sigNote(c.sig) }
}

function loadRoster($: EngineInterface): Promise<void> {
  rosterLoad ??= (async () => {
    try {
      const r = await $.process.run(['sh', '-c', '"$HOME/dotfiles/roleplay/bin/roleplay-roll" --roster'], { timeoutMs: 5000 })
      roster = parseRoster(r.stdout)
      // Nothing read: try again at the next need rather than never.
      if (!roster.length) rosterLoad = null
      await dbg($, `roster ${roster.length} rows`)
    } catch (err) {
      // A timeout or a failed start: also try again at the next need.
      rosterLoad = null
      await dbg($, `roster error ${String(err)}`)
    }
  })()
  return rosterLoad
}

async function sessionMode($: EngineInterface): Promise<Mode> {
  const p = await read($, pin)
  if (p.mode) return p.mode
  const saved = await $.store.get('mode')
  return isMode(saved) ? saved : 'random'
}

// Each session's mode and character, saved under its own key `pin:<session
// id>`, so a resume gets them back, and so does a mod reload that comes back
// without the session's $.state (seen 2026-11-17: a session-mode session got
// a new character at a reload). One key per session: the old single `pins`
// map was read, changed and written whole by every open session, so two
// sessions saving at once lost one pin. That map is still read for a pin
// saved before the change. The newest PINS_KEPT keys stay.
const PINS_KEPT = 200
const PIN_KEY = 'pin:'
type SavedPins = Record<string, Pin>
async function savePin($: EngineInterface, p: Pin) {
  try {
    const key = PIN_KEY + (await $.session.id())
    // Delete first, so the key moves to the end of the store's order.
    await $.store.delete(key)
    await $.store.set(key, p)
    const keys = (await $.store.keys()).filter(k => k.startsWith(PIN_KEY))
    for (const k of keys.slice(0, Math.max(0, keys.length - PINS_KEPT))) await $.store.delete(k)
  } catch (err) {
    await dbg($, `save pin error ${String(err)}`)
  }
}

async function loadPin($: EngineInterface, sid: string): Promise<Pin | null> {
  const own = (await $.store.get(PIN_KEY + sid)) as Pin | undefined
  const saved = own ?? ((await $.store.get('pins')) as SavedPins | undefined)?.[sid]
  return saved && isMode(saved.mode) ? { ...saved, universe: saved.universe ?? null } : null
}

// Writes the session's pin and saves it under the session id.
async function setPin($: EngineInterface, fn: (p: Pin) => Pin): Promise<Pin> {
  const p = await update($, pin, fn)
  await savePin($, p)
  return p
}

// The session id whose saved pin was already looked at. A resume or /clear
// moves to another id, which is then looked up once.
let restoredFor = ''
async function restorePin($: EngineInterface): Promise<Pin> {
  const sid = await $.session.id()
  const now = await read($, pin)
  if (restoredFor === sid) return now
  restoredFor = sid
  const saved = await loadPin($, sid)
  // A session with nothing saved saves what it has now, random mode too: else
  // a reload without $.state would give it the saved default mode instead.
  if (!saved && now.mode) await savePin($, now)
  if (now.who || now.universe || !saved) return now
  await dbg($, `restore pin ${sid} mode=${saved.mode} who=${saved.who?.name ?? 'none'} universe=${saved.universe ?? 'none'}`)
  return update($, pin, x => (x.who || x.universe ? x : saved))
}

// A new session character, never the current one. Falls back to the script
// (no --votes: nothing logged, no vote id) when the roster did not load; its
// tag carries no signature line, so that character gets no signature note.
async function rollChar($: EngineInterface, not?: string): Promise<Char | null> {
  await loadRoster($)
  const c = pickChar(roster, Math.random(), not)
  if (c) return c
  for (let i = 0; i < 4; i++) {
    const w = await ownRoll($, false)
    if (!w) return null
    if (w.name !== not || i === 3) return { universe: w.universe, name: w.name, emoji: w.emoji, traits: w.traits, sig: '', u: 0, c: 0 }
  }
  return null
}

// A new session universe, never the current one. Falls back to the script's
// own roll (its universe) when the roster did not load.
async function rollUniverse($: EngineInterface, not?: string): Promise<string | null> {
  await loadRoster($)
  const u = pickUniverse(roster, Math.random(), not)
  if (u) return u
  for (let i = 0; i < 4; i++) {
    const w = await ownRoll($, false)
    if (!w) return null
    if (w.universe !== not || i === 3) return w.universe
  }
  return null
}

function universeToast($: EngineInterface, u: string) {
  $.ui.toast(`🎭 This session's universe: ${titleCase(u)}`)
}

// Picking the universe already pinned keeps the last character, so the next
// roll still skips it.
async function setUniverse($: EngineInterface, u: string) {
  const was = (await read($, pin)).universe ?? null
  await setPin($, (p): Pin => ({ ...p, mode: 'universe', universe: u }))
  if (was !== u) lastInUniverse = ''
  universeToast($, u)
}

// A universe roll that printed nothing: nobody in `u` can roll (all off, or
// the universe was renamed after the roster loaded). Reads the roster again
// and pins another universe, unless something else changed the pin first.
async function replaceUniverse($: EngineInterface, u: string) {
  rosterLoad = null
  const next = await rollUniverse($, u)
  await dbg($, `universe ${u} gave no roll; now ${next ?? 'none'}`)
  if (!next) return
  const p = await setPin($, (x): Pin => (x.mode === 'universe' && x.universe === u ? { ...x, universe: next } : x))
  if (p.universe !== next) return
  lastInUniverse = ''
  $.ui.toast(`🎭 Nobody in ${titleCase(u)} can roll. This session's universe: ${titleCase(next)}`)
}

async function setChar($: EngineInterface, c: Char) {
  await dbg($, `pick who=${c.name}`)
  await setPin($, (p): Pin => ({ ...p, mode: 'session', who: c }))
  $.ui.toast(`🎭 This session: «${c.name}» ${c.emoji} ${c.universe}`)
}

// Rolls a new character, or in universe mode a new universe. A Pick made
// while it rolled wins.
async function reroll($: EngineInterface, from: string) {
  try {
    const p0 = await read($, pin)
    await dbg($, `reroll from=${from} mode=${p0.mode ?? 'none'} who=${p0.who?.name ?? 'none'} universe=${p0.universe ?? 'none'}`)
    if (p0.mode === 'universe') {
      const was = p0.universe ?? null
      const u = await rollUniverse($, was ?? undefined)
      if (!u) {
        $.ui.toast('🎭 Reroll found no universe: see mod-debug.log')
        return
      }
      // Only if nothing changed meanwhile: not the universe (a Pick), not the
      // mode (a switch to another mode while this rolled).
      const p = await setPin($, (x): Pin =>
        x.mode === 'universe' && (x.universe ?? null) === was ? { ...x, universe: u } : x,
      )
      if (p.universe === u) {
        lastInUniverse = ''
        universeToast($, u)
      }
      return
    }
    const now = p0.who
    const c = await rollChar($, now?.name)
    if (!c) {
      $.ui.toast('🎭 Reroll found no character: see mod-debug.log')
      return
    }
    // /roleplay reroll from random mode moves to session mode; from session
    // mode it applies only if the session is still in session mode.
    const p = await setPin($, (x): Pin =>
      x.mode === p0.mode && x.who?.name === now?.name ? { ...x, mode: 'session', who: c } : x,
    )
    if (p.who?.name === c.name) $.ui.toast(`🎭 This session: «${c.name}» ${c.emoji} ${c.universe}`)
  } catch (err) {
    $.ui.toast(`🎭 Reroll failed: ${String(err)}`)
  }
}

// /roleplay random|session|universe and the row's mode button: this
// session's mode and the saved default for new sessions. Into universe mode
// from session mode, the session character's universe; from random mode,
// the universe this session last had, if any.
async function setMode($: EngineInterface, mode: Mode, say: boolean) {
  await dbg($, `set mode=${mode} from=${say ? 'command' : 'button'}`)
  await $.store.set('mode', mode)
  // From session mode into universe mode: the universe of the character the
  // session had, and the first roll in it is someone else.
  const was = await read($, pin)
  const carry = mode === 'universe' && was.mode === 'session' && was.who ? was.who : null
  const p = await startSession($, await setPin($, (x): Pin => ({ ...x, mode, ...(carry ? { universe: carry.universe } : {}) })))
  if (carry) lastInUniverse = carry.name
  if (!say) return
  $.ui.toast(
    mode === 'random'
      ? '🎭 Random mode: a new character on each prompt. New sessions start this way too.'
      : mode === 'universe'
        ? `🎭 Universe mode: a new character on each prompt${p.universe ? `, from ${titleCase(p.universe)}` : ''}. New sessions start this way too.`
        : `🎭 Session mode${p.who ? `: «${p.who.name}» ${p.who.emoji} ${p.who.universe}` : ''}. New sessions start this way too.`,
  )
}

async function openPicker($: EngineInterface) {
  await loadRoster($)
  if (!roster.length) {
    $.ui.toast('🎭 The roster did not load: see mod-debug.log')
    return
  }
  // An open pane keeps the text in its field, so keep the filter too.
  if (!(await $.ui.panes()).some(x => x.id === PICK)) await update($, filter, () => '')
  // Transparent: the pane's default backdrop is too dark to read on this
  // terminal (plainify hit the same).
  const title = (await read($, pin)).mode === 'universe' ? 'Pick a universe' : 'Pick a character'
  const r = await $.ui.open({ id: PICK, title, focus: true, closeOnEscape: true, backgroundColor: 'transparent' })
  if (!r.isPlaced) $.ui.toast(`🎭 The pick list did not open: ${r.reason}`)
}

// Gets back a resumed session's saved pin; then, in session mode with no
// character yet, rolls one, quietly: the row shows it. In universe mode it
// does the same for the universe, and also rolls a new one when the pinned
// universe is no longer in the roster (an old pin, a renamed universe), or
// every prompt would get no bookend. `given` is the pin a caller has just
// written, so this need not read it back.
async function startSession($: EngineInterface, given?: Pin): Promise<Pin> {
  let p = given ?? (await restorePin($))
  try {
    if (p.mode === 'universe') {
      const was = p.universe ?? null
      if (was) {
        await loadRoster($)
        if (!roster.length || roster.some(c => c.universe === was)) return p
      }
      const u = await rollUniverse($)
      if (u) p = await setPin($, x => ({ ...x, universe: (x.universe ?? null) === was ? u : x.universe }))
      await dbg($, `universe roll ${u ?? 'none'}${was ? ` (was ${was}, gone from the roster)` : ''}`)
      return p
    }
    if (p.mode !== 'session' || p.who) return p
    const c = await rollChar($)
    if (c) p = await setPin($, x => ({ ...x, who: x.who ?? c }))
    await dbg($, `session roll who=${c ? c.name : 'none'}`)
  } catch (err) {
    await dbg($, `session roll error ${String(err)}`)
  }
  return p
}

async function choose($: EngineInterface, c: Char) {
  await setChar($, c)
  await $.ui.close({ id: PICK })
}

async function chooseUniverse($: EngineInterface, u: string) {
  await setUniverse($, u)
  await $.ui.close({ id: PICK })
}

// Universes that can roll (share above 0) whose name holds every word of the
// search.
export function matchUniverses(all: readonly Char[], q: string): Universe[] {
  const words = q.toLowerCase().split(/\s+/).filter(Boolean)
  return universes(all).filter(x => x.u > 0 && words.every(w => x.name.toLowerCase().includes(w)))
}

// Sets one vote in votes.tsv, in the line the rolevote Hammerspoon seed
// writes: time, id, place, vote, kind, name, the roll's own time from
// rolls.tsv, and an empty line field. It drops any line for the same id,
// roll time, place and kind, so a vote changed or cleared leaves one line or
// none; the roll time tells apart two rolls that drew the same id. $3 empty
// only clears. The new file is written whole to a temp file and renamed in
// one step, under a lock (lockf), so two writers cannot lose each other's
// line and a failure leaves the old file. Arguments go in as $1..$5, never
// into the script text: VOTE_LOCK runs VOTE_SH, passed as its $0.
const VOTE_SH = [
  'd="$HOME/.local/state/roleplay"; f="$d/votes.tsv"; t="$f.tmp.$$"',
  `rolled=$(awk -F'\\t' -v id="$1" '$2 "" == id "" { t = $1 } END { print t }' "$d/rolls.tsv" 2>/dev/null)`,
  `name=$(printf '%s' "$5" | tr '\\t\\r\\n' '   ')`,
  '(',
  `  if [ -f "$f" ]; then awk -F'\\t' -v id="$1" -v r="$rolled" -v p="$2" -v k="$4" '!($2 "" == id "" && $7 "" == r "" && $3 == p && $5 == k)' "$f" || exit 1; fi`,
  `  if [ -n "$3" ]; then printf '%s\\t%s\\t%s\\t%s\\t%s\\t%s\\t%s\\t\\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" "$2" "$3" "$4" "$name" "$rolled"; fi`,
  ') > "$t" && mv "$t" "$f" || { rm -f "$t"; exit 1; }',
].join('\n')
const VOTE_LOCK =
  'd="$HOME/.local/state/roleplay"; mkdir -p "$d" || exit 1; exec /usr/bin/lockf -k -t 4 "$d/votes.lock" /bin/sh -c "$0" sh "$@"'
// Slot within a bookend (1-4): what the vote is on, and which way.
const SLOTS: Record<number, [Kind, Way]> = {
  1: ['character', 'up'], 2: ['character', 'down'], 3: ['universe', 'up'], 4: ['universe', 'down'],
}

// What a press does, given the vote standing on that part: none → cast,
// the same → clear, the other → change.
export function nextVote(standing: Way | undefined, pressed: Way): Way | undefined {
  return standing === pressed ? undefined : pressed
}

// Presses run one at a time, in order, and each works out its vote from the
// one before it: two quick presses on a button cast and then clear. The
// module's copy of myVotes is filled from the state on first use (after a
// reload, too) and leads it.
let voteChain: Promise<void> = Promise.resolve()
let standingNow: Record<string, Way> | null = null

function castVote($: EngineInterface, l: Line, place: 'opener' | 'closer', n: number): Promise<void> {
  voteChain = voteChain.then(() => castOne($, l, place, n)).catch(err => dbg($, `vote error ${String(err)}`))
  return voteChain
}

async function castOne($: EngineInterface, l: Line, place: 'opener' | 'closer', n: number) {
  const id = l.voteId
  const slot = SLOTS[n]
  if (!id || !slot) return
  const [kind, pressed] = slot
  const k = `${id}:${place}:${kind}`
  const name = kind === 'character' ? l.name : l.universe
  standingNow ??= { ...(await read($, myVotes)) }
  const next = nextVote(standingNow[k], pressed)
  try {
    const r = await $.process.run(
      ['sh', '-c', VOTE_LOCK, VOTE_SH, id, place, next ?? '', kind, name],
      { timeoutMs: 6000 },
    )
    if (r.exitCode !== 0) throw new Error(r.stderr.trim() || `exit ${r.exitCode}`)
  } catch (err) {
    $.ui.toast(`Vote not saved: ${String(err)}`)
    return
  }
  const now = { ...standingNow }
  if (next) now[k] = next
  else delete now[k]
  standingNow = now
  await update($, myVotes, () => now)
  $.ui.toast(next ? `${next === 'up' ? '+' : '−'} ${name}` : `Vote cleared: ${name}`)
  await countVotes($).catch(err => dbg($, `vote count error ${String(err)}`))
}

// Sets one row and drops the oldest past KEEP, so the maps (and the rows
// that read them) stay small in a long session.
export function withRow(m: Record<string, Line>, key: string, line: Line): Record<string, Line> {
  const next: Record<string, Line> = { ...m }
  delete next[key]
  next[key] = line
  const keys = Object.keys(next)
  for (const k of keys.slice(0, Math.max(0, keys.length - KEEP))) delete next[k]
  return next
}

async function setRow($: EngineInterface, kind: 'opener' | 'closer', key: string, line: Line) {
  if (kind === 'opener') await update($, openers, m => withRow(m, key, line))
  else await update($, closers, m => withRow(m, key, line))
}

async function dbg($: EngineInterface, msg: string) {
  if (!DEBUG) return
  try {
    await $.process.run(
      ['sh', '-c', 'mkdir -p "$HOME/.local/state/roleplay" && cat >> "$HOME/.local/state/roleplay/mod-debug.log"'],
      { stdin: `${new Date().toISOString()} ${msg}\n`, timeoutMs: 5000 },
    )
  } catch {
    // nothing to do
  }
}

// The hook's roll for a prompt: the newest rolls.tsv line logged within a
// few seconds of that prompt's Enter (the hook rolls at Enter, even for a
// prompt that is queued), whose vote id no turn has used yet.
async function hookRoll($: EngineInterface, submittedAt: number): Promise<Who | null> {
  const r = await $.process.run(
    [
      'sh', '-c',
      'tail -5 "${XDG_STATE_HOME:-$HOME/.local/state}/roleplay/rolls.tsv"; echo ---; cat "$HOME/dotfiles/roleplay/roster.tsv"',
    ],
    { timeoutMs: 5000 },
  )
  const [rollPart = '', rosterPart = ''] = r.stdout.split('\n---\n')
  const rolls = rollPart.split('\n').filter(Boolean).reverse()
  for (const line of rolls) {
    const [when = '', voteId = '', name = '', universe = ''] = line.split('\t')
    const at = new Date(when.replace(' ', 'T')).getTime()
    if (!voteId || usedVotes.has(voteId) || Math.abs(at - submittedAt) > 5000) continue
    for (const row of rosterPart.split('\n')) {
      if (row.trimStart().startsWith('#')) continue
      const f = row.split('|').map(x => x.trim())
      if (f.length < 4 || f[0] !== universe || f[1] !== name) continue
      // The hook's 1/3 signature draw is not logged, so draw again.
      return { name, emoji: f[2]!, universe, traits: f[3]!, extra: sigNote(f[4] ?? ''), voteId }
    }
  }
  return null
}

// The mod's own roll. --votes logs it and puts a vote id in the tag, so the
// vote links work as the hook's did. Its output is the hook's JSON envelope.
// `universe` rolls only within that universe and `not` skips one character
// (universe mode). Names hold spaces, so they go in as arguments ("$@"),
// never into the script text; the first word after it is $0.
async function ownRoll($: EngineInterface, votes = true, universe?: string, not?: string): Promise<Who | null> {
  const args = [
    ...(votes ? ['--votes'] : []),
    ...(universe ? [`--universe=${universe}`] : []),
    ...(not ? [`--not=${not}`] : []),
  ]
  const r = await $.process.run(
    ['sh', '-c', '"$HOME/dotfiles/roleplay/bin/roleplay-roll" "$@"', 'sh', ...args],
    { timeoutMs: 5000 },
  )
  try {
    const tag = JSON.parse(r.stdout)?.hookSpecificOutput?.additionalContext
    return typeof tag === 'string' ? parseWho(tag) : null
  } catch {
    return null
  }
}

// Counts the votes after the last review (local times in both files).
async function countVotes($: EngineInterface) {
  const r = await $.process.run(
    [
      'sh', '-c',
      'd="$HOME/.local/state/roleplay"; cat "$d/votes-reviewed-at" 2>/dev/null; echo; echo ---; cat "$d/votes.tsv" 2>/dev/null',
    ],
    { timeoutMs: 5000 },
  )
  const [head = '', body = ''] = r.stdout.split('\n---\n')
  const local = (s: string) => new Date(s.trim().replace(' ', 'T')).getTime()
  const since = head.trim() ? local(head) : 0
  const now = Date.now()
  let waiting = 0
  let old = 0
  for (const row of body.split('\n')) {
    const at = local(row.split('\t')[0] ?? '')
    if (Number.isNaN(at) || at <= since) continue
    waiting++
    if (now - at >= WEEK_MS) old++
  }
  await update($, votes, () => ({ waiting, old }))
}

async function write(
  $: EngineInterface, kind: 'opener' | 'closer', key: string, w: Who, ask: string, turnId: string,
) {
  const t0 = await $.clock.now()
  let text: string | null = null
  let failed: string | undefined
  try {
    const r = await $.model.complete({ model: MODEL, system: SYS, prompt: ask, maxTokens: 1000, timeoutMs: 30000 })
    if (r.isAnswered) {
      text = norm(r.text).replace(/^["“*]+|["”*]+$/g, '') || null
      if (!text) failed = 'empty reply'
    } else failed = r.reason
  } catch (err) {
    failed = `refused: ${String(err)}`
  }
  const ms = (await $.clock.now()) - t0
  await dbg($, `write ${kind} ${turnId} ms=${ms} ${failed ?? 'ok'}`)
  const line: Line = { ...pendingLine(w), text, ms, ...(failed ? { failed } : {}) }
  await setRow($, kind, key, line)
  const sessionId = await $.session.id()
  const rec = JSON.stringify({
    at: new Date(t0).toISOString(), session: sessionId, turn: turnId, voteId: w.voteId ?? null,
    kind, model: MODEL, ms, name: w.name, universe: w.universe, text, failed,
  })
  await $.process.run(
    ['sh', '-c', 'mkdir -p "$HOME/.local/state/roleplay" && cat >> "$HOME/.local/state/roleplay/mod-lines.jsonl"'],
    { stdin: rec + '\n', timeoutMs: 5000 },
  )
}

// Rolls the character (settling `rolled` either way), then writes the opener.
async function startOpener(
  $: EngineInterface, turnId: string, text: string, submittedAt: number, rolled: (w: Who | null) => void,
) {
  let w: Who | null = null
  try {
    let via: string
    // After a resume or /clear, the first prompt may come before the
    // scheduled restore or roll: do both here too (each runs once).
    const p = await startSession($)
    if (p.mode === 'session') {
      via = 'session'
      w = p.who ? whoFor(p.who) : null
    } else if (p.mode === 'universe' && p.universe) {
      via = 'universe'
      const u = p.universe
      w = await ownRoll($, true, u, lastInUniverse || undefined)
      const fell = !w
      if (w) lastInUniverse = w.name
      else {
        // Nobody in it can roll: this turn gets a random roll, and the
        // session another universe.
        via = 'universe gave none, own roll'
        w = await ownRoll($)
        $.clock.after(0, () => replaceUniverse($, u).catch(err => dbg($, `replace universe error ${String(err)}`)))
      }
      await loadRoster($)
      const c = w ? roster.find(x => x.name === w!.name && x.universe === w!.universe) : undefined
      // The character's share within the universe, and the universe's own;
      // a fallback roll's odds are random mode's.
      if (w && c) w = { ...w, odds: { c: fell ? c.c : c.u > 0 ? c.c / c.u : 0, u: c.u } }
    } else {
      // Random mode, and universe mode while it has no universe yet.
      w = HOOK_ROLLS ? await hookRoll($, submittedAt) : null
      via = w ? 'hook roll' : 'own roll'
      if (!w) w = await ownRoll($)
      await loadRoster($)
      const c = w ? roster.find(x => x.name === w!.name && x.universe === w!.universe) : undefined
      if (w && c) w = { ...w, odds: { c: c.c, u: c.u } }
    }
    await dbg($, `opener ${turnId} who=${w ? w.name : 'none'} via=${via}`)
  } finally {
    rolled(w)
  }
  if (!w) return
  if (w.voteId) usedVotes.add(w.voteId)
  const key = headKey(text)
  prompts.delete(key)
  prompts.set(key, { full: norm(text), lines: lineCount(text) })
  for (const k of [...prompts.keys()].slice(0, Math.max(0, prompts.size - KEEP))) prompts.delete(k)
  await setRow($, 'opener', key, pendingLine(w))
  const ask =
    `Character: ${w.name} (${w.universe}) — ${w.traits}${w.extra ? `\nNote: ${w.extra}` : ''}\n` +
    exampleBlock(w.name) +
    (lastAnswer ? `\nThe assistant's previous reply ended:\n${lastAnswer.slice(-1500)}\n` : '') +
    `\nThe user just asked:\n${text.slice(-3000)}\n\n` +
    'Write the OPENER: the line at the top of the reply, reacting to this request as the work begins.'
  await write($, 'opener', key, w, ask, turnId)
}

async function startCloser($: EngineInterface, turnId: string, t: Turn, answerText: string) {
  const w = await t.roll
  if (!w) return
  const key = tailKey(answerText)
  await setRow($, 'closer', key, pendingLine(w))
  const answer = answerText.replace(/^>\s*🎭.*$\n?/gm, '').trim()
  const ask =
    `Character: ${w.name} (${w.universe}) — ${w.traits}${w.extra ? `\nNote: ${w.extra}` : ''}\n` +
    exampleBlock(w.name) +
    `\nThe user asked:\n${t.prompt.slice(-2000)}\n\nThe assistant's reply:\n${answer.slice(-6000)}\n\n` +
    'Write the CLOSER: the line at the bottom of the reply. A closing line, a salute, a brief scene beat, ' +
    'or a quip about how the task went.'
  await write($, 'closer', key, w, ask, turnId)
}

export const register: Register = on => {
  // Nothing here waits on a process: examples.md (read here only, so an edit
  // reaches a session at its next start or mod reload) and the vote count
  // load on timers. The count also refreshes every 10 minutes, so a review
  // finished in another session clears this one's reminder row.
  on('session.start', async ($, e, next) => {
    $.clock.after(0, async () => {
      try {
        const r = await $.process.run(['sh', '-c', 'cat "$HOME/dotfiles/roleplay/examples.md"'], { timeoutMs: 5000 })
        examples = r.exitCode === 0 ? r.stdout : ''
      } catch (err) {
        await dbg($, `examples read error ${String(err)}`)
      }
    })
    // A reload kills calls in flight; their rows would say "thinking" forever.
    const stale = (m: Record<string, Line>) =>
      Object.fromEntries(Object.entries(m).map(([k, l]) => [k, l.text || l.failed ? l : { ...l, failed: 'cut off by a mod reload' }]))
    await update($, openers, stale)
    await update($, closers, stale)
    $.clock.after(0, () => countVotes($).catch(err => dbg($, `vote count error ${String(err)}`)))
    $.clock.every(10 * 60 * 1000, () => countVotes($).catch(err => dbg($, `vote count error ${String(err)}`)))
    await $.command.register({
      name: 'roleplay',
      description: 'Roleplay bookends: a new character each prompt, from one universe, or one character per session',
      argumentHint: 'random | universe | session | reroll | pick',
      immediate: true,
    })
    // The mode: the session's own after a reload, else the saved default; a
    // resumed session's saved pin then replaces both. A session-mode session
    // rolls its character now, so the row shows it; a reload keeps its own.
    const had = await read($, pin)
    const mode = await sessionMode($)
    await update($, pin, p => ({ ...p, mode }))
    // Whether $.state came through this load: a reload should keep it.
    void dbg($, `start ${await $.session.id()} state mode=${had.mode ?? 'none'} who=${had.who?.name ?? 'none'} universe=${had.universe ?? 'none'}`)
    $.clock.after(0, () => {
      void loadRoster($)
      return startSession($).then(() => undefined)
    })
    return next(e)
  })

  // /clear (and an in-process resume) ends the session with no new
  // session.start, and the process goes on under another session id: forget
  // the old conversation's turns, lines and character. The new id's saved pin
  // comes back if it has one (a resume); otherwise a session-mode session
  // rolls a new character. Not on a real exit: nothing would show it.
  on('session.end', async ($, e, next) => {
    resetSession()
    await update($, openers, () => ({}))
    await update($, closers, () => ({}))
    if (e.reason === 'clear' || e.reason === 'resume') {
      await update($, pin, p => ({ ...p, who: null, universe: null }))
      // The id may not have moved on yet when the timer fires: wait for it,
      // briefly, so the old session's pin is neither restored nor overwritten.
      restoredFor = e.sessionId
      const ended = e.sessionId
      let tries = 0
      const later = async (): Promise<void> => {
        if ((await $.session.id()) === ended && ++tries < 20) {
          $.clock.after(250, later)
          return
        }
        await startSession($)
      }
      $.clock.after(0, later)
    }
    return next(e)
  })

  // /roleplay random|universe|session sets this session's mode and the saved
  // default. In universe mode reroll and pick change the universe; otherwise
  // they change the character and put this session in session mode. Bare
  // /roleplay says where things stand. Answers are toasts: a command's text
  // would reach the main model.
  on('command.run', { command: 'roleplay' }, async ($, e) => {
    const arg = e.args.trim().toLowerCase()
    if (isMode(arg)) await setMode($, arg, true)
    else if (arg === 'reroll') await reroll($, 'command')
    else if (arg === 'pick') await openPicker($)
    else {
      const p = await read($, pin)
      const now =
        p.mode === 'session' && p.who
          ? `session mode, «${p.who.name}»`
          : p.mode === 'universe' && p.universe
            ? `universe mode, ${titleCase(p.universe)}`
            : `${p.mode ?? 'random'} mode`
      $.ui.toast(`🎭 Roleplay: ${now}. /roleplay random | universe | session | reroll | pick`)
    }
    return {}
  })

  // Submit only notes a typed prompt, before next(e): for an idle prompt,
  // next(e) resolves after the turn has started.
  on('prompt.submit', async ($, e, next) => {
    const isTyped = !e.command && (!e.origin || e.origin.kind === 'composer') && norm(e.text) !== ''
    const entry = { text: e.text, at: Date.now() }
    if (isTyped) queue = [...queue, entry].slice(-5)
    const result = await next(e)
    if (isTyped && result.drop !== undefined) queue = queue.filter(q => q !== entry)
    return result
  })

  // The opener starts on a timer, so the turn never waits on it.
  on('turn.start', ($, e, next) => {
    if (e.agentId || !e.text) return next(e)
    const q = takeQueued(e.text, Date.now())
    if (!q) return next(e)
    const turnId = e.turnId
    let rolled: (w: Who | null) => void = () => {}
    const roll = new Promise<Who | null>(resolve => {
      rolled = resolve
    })
    turns.set(turnId, { roll, prompt: q.text })
    $.clock.after(0, () =>
      startOpener($, turnId, q.text, q.at, rolled).catch(err => dbg($, `opener error ${turnId} ${String(err)}`)),
    )
    return next(e)
  })

  // Only a turn that got an opener gets a closer: not a notification's turn,
  // not a subagent's. The turn's own state comes from the map, so a queued
  // prompt's turn starting meanwhile cannot change it.
  on('turn.complete', async ($, e, next) => {
    const t = e.agentId ? undefined : turns.get(e.turnId)
    if (t) turns.delete(e.turnId)
    const result = await next(e)
    if (!e.agentId) $.clock.after(0, () => countVotes($).catch(err => dbg($, `vote count error ${String(err)}`)))
    if (!t || e.isAborted || e.reason !== 'answer' || !e.answer) return result
    lastAnswer = e.answer
    const turnId = e.turnId
    const answer = e.answer
    $.clock.after(0, () =>
      startCloser($, turnId, t, answer).catch(err => dbg($, `closer error ${turnId} ${String(err)}`)),
    )
    return result
  })

  // Above the prompt, always: a dim row with the mode button (it shows the
  // mode; a press moves to the next of random → session → universe and saves
  // the default), Reroll and Pick outside random mode, then the character,
  // the universe, or what random mode does. Buttons first, so
  // they stay put when the name's length changes. Under it, the vote reminder
  // when it is due.
  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    if (e.props.hasSurvey) return next(e)
    const v = await read($, votes)
    const due = v.old > VOTES_OLD || v.waiting > VOTES_MANY
    const p = await read($, pin)
    const mode: Mode = p.mode ?? 'random'
    const isPinned = mode !== 'random'
    const { Box, Text, Button } = $.ui.resolve(e)
    const shown =
      mode === 'random'
        ? 'a new character each prompt'
        : mode === 'universe'
          ? p.universe
            ? `a new character each prompt from ${titleCase(p.universe)}`
            : 'rolling a universe…'
          : p.who
            ? `«${p.who.name}» ${p.who.emoji} ${p.who.universe}`
            : 'rolling a character…'
    const nextMode = MODES[(MODES.indexOf(mode) + 1) % MODES.length]!
    const sessionRow = (
      <Box key="rp-session" flexDirection="row" columnGap={1}>
        <Text dimColor>🎭</Text>
        <Button
          key="rp-mode"
          label={mode}
          dimColor
          onPress={() => setMode($, nextMode, false)}
        />
        {isPinned ? <Button key="rp-reroll" label="Reroll" dimColor onPress={() => reroll($, 'button')} /> : null}
        {/* Not in random mode: a pick there would quietly switch modes. */}
        {isPinned ? <Button key="rp-pick" label="Pick" dimColor onPress={() => openPicker($)} /> : null}
        <Text dimColor>{shown}</Text>
      </Box>
    )
    if (!due && !VOTES_DEMO) return sessionRow
    const what = v.old > VOTES_OLD ? `${v.waiting} roleplay votes waiting, ${v.old} over a week old` : `${v.waiting} roleplay votes waiting`
    const voteRow = (
      <Box key="rp-votes" flexDirection="row" columnGap={1}>
        <Text>🎭 {what}{due ? '' : ' (demo)'}</Text>
        <Button
          key="rolevotes"
          label="Review"
          onPress={async () => {
            // One tab per press: a second press within 30 s does nothing.
            const now = Date.now()
            if (now - lastReviewPress < 30000) return
            lastReviewPress = now
            try {
              const r = await $.process.run(['sh', '-c', '"$HOME/dotfiles/bin/rolevotes-review"'], { timeoutMs: 15000 })
              if (r.exitCode !== 0) $.ui.toast(`Vote review did not open: ${r.stderr.trim() || `exit ${r.exitCode}`}`)
            } catch (err) {
              $.ui.toast(`Vote review did not open: ${String(err)}`)
            }
          }}
        />
      </Box>
    )
    return (
      <Box flexDirection="column">
        {sessionRow}
        {voteRow}
      </Box>
    )
  })

  // The Pick list: a search field and one row per match. Enter in the field
  // takes the first match; a row takes its character, or in universe mode
  // its universe. Escape closes.
  on('ui.render', { component: 'Pane', requestId: PICK }, async ($, e) => {
    const { Box, Text, Button, Input } = $.ui.resolve(e)
    const q = await read($, filter)
    const p = await read($, pin)
    if (p.mode === 'universe') {
      const hits = matchUniverses(roster, q)
      return (
        <Box flexDirection="column">
          <Input
            key="rp-filter"
            autoFocus
            placeholder="type part of a universe"
            submitLabel="pick first"
            onInput={value => update($, filter, () => value)}
            onSubmit={value => {
              const x = value.trim() ? matchUniverses(roster, value)[0] : undefined
              if (x) void chooseUniverse($, x.name)
            }}
          />
          {hits.length === 0 ? <Text dimColor>No universe matches.</Text> : null}
          {hits.map(x => (
            <Button key={`rp-u:${x.name}`} plain onPress={() => chooseUniverse($, x.name)}>
              <Text italic color="permission">{titleCase(x.name)}</Text>{' '}
              <Text dimColor>
                {pct(x.u)} · {x.members} {x.members === 1 ? 'character' : 'characters'}
                {p.universe === x.name ? ' · now' : ''}
              </Text>
            </Button>
          ))}
        </Box>
      )
    }
    const now = p.who
    const hits = matches(roster, q)
    return (
      <Box flexDirection="column">
        <Input
          key="rp-filter"
          autoFocus
          placeholder="type part of a name or universe"
          submitLabel="pick first"
          onInput={value => update($, filter, () => value)}
          onSubmit={value => {
            // Enter on an empty field picks nothing.
            const c = value.trim() ? matches(roster, value)[0] : undefined
            if (c) void choose($, c)
          }}
        />
        {hits.length === 0 ? <Text dimColor>No character matches.</Text> : null}
        {hits.map(c => (
          <Button key={`rp-c:${c.universe}|${c.name}`} plain onPress={() => choose($, c)}>
            {/* As a bookend's head: name, its odds, universe, the universe's odds. */}
            {c.emoji} {c.name} <Text dimColor>{pct(c.c)}</Text> <Text italic color="permission">{c.universe}</Text>{' '}
            <Text dimColor>{pct(c.u)}{now?.name === c.name ? ' · now' : ''}</Text>
          </Button>
        ))}
      </Box>
    )
  })

  on('ui.render', { component: 'UserMessage' }, async ($, e, next) => {
    const inner = await next(e)
    // Only rows the user typed; a notification or peer message is never one.
    if (e.props.origin.kind !== 'composer') return inner
    const l = findOpener(await read($, openers), e.props.text)
    if (!l) return inner
    const { Box } = $.ui.resolve(e)
    return (
      <Box flexDirection="column">
        {inner}
        <Box marginTop={1}>{bookend($, e, l, 'opener', await read($, myVotes))}</Box>
      </Box>
    )
  })

  on('ui.render', { component: 'AssistantMessage' }, async ($, e, next) => {
    const inner = await next(e)
    if (e.props.isSummary) return inner
    const l = (await read($, closers))[tailKey(e.props.text)]
    if (!l) return inner
    const { Box } = $.ui.resolve(e)
    return (
      <Box flexDirection="column">
        {inner}
        <Box marginTop={1}>{bookend($, e, l, 'closer', await read($, myVotes))}</Box>
      </Box>
    )
  })
}

// Display width of a string in terminal cells: wide emoji count 2, joiners
// and variation selectors 0. Close enough to lay out by hand.
function cells(t: string): number {
  let n = 0
  for (const ch of t) {
    const c = ch.codePointAt(0)!
    if (c === 0x200d || (c >= 0xfe00 && c <= 0xfe0f) || (c >= 0x1f3fb && c <= 0x1f3ff)) continue
    n += c >= 0x1f000 || (c >= 0x2600 && c <= 0x27bf) || (c >= 0x2e80 && c <= 0xa4cf) || c === 0x2b50 ? 2 : 1
  }
  return n
}

// Greedy word wrap: the first row has `first` cells, the rest `rest`.
function wrapWords(t: string, first: number, rest: number): string[] {
  const rows: string[] = []
  let cur = ''
  let room = first
  for (const w of t.split(' ')) {
    const next = cur ? `${cur} ${w}` : w
    if (cur && cells(next) > room) {
      rows.push(cur)
      cur = w
      room = rest
    } else cur = next
  }
  rows.push(cur)
  return rows
}

// A universe in capitals, as the roster writes it, in title case:
// GHOST IN THE SHELL → Ghost in the Shell. Words with a digit stay (40K).
const SMALL = new Set(['a', 'an', 'and', 'at', 'by', 'for', 'in', 'of', 'on', 'or', 'the', 'to'])
export function titleCase(s: string): string {
  if (s !== s.toUpperCase()) return s
  return s.split(' ').map((w, i) => {
    if (/\d/.test(w)) return w
    const lo = w.toLowerCase()
    return i > 0 && SMALL.has(lo) ? lo : lo.charAt(0).toUpperCase() + lo.slice(1)
  }).join(' ')
}

// One bookend, drawn like a blockquote in the reply: indented to the reply's
// text, a dim bar on every row. Three parts, each on rows of its own:
//   ▎ 🎭 Name emoji · Universe                     (dim; split in two if narrow)
//   ▎ "line"   (model kind 1.2s)
//   ▎ 1.2% [ − ] [ + ]   8.5% [ − ] [ + ]          (random and universe mode)
// Rows are wrapped by hand so the bar runs down each one; a row of several
// Texts in one flex row wraps each Text in its own column instead. The vote
// buttons use roleplay-roll's vote id and the old link slots: 1–4 on the
// opener, 5–8 on the closer, numbered character +, character −, universe +,
// universe −; drawn minus first. A press appends to votes.tsv (castVote).
const INDENT = 2
const BAR = '▎ '
function bookend(
  $: EngineInterface, e: Parameters<EngineInterface['ui']['resolve']>[0] & { viewport?: { columns: number } },
  l: Line, kind: 'opener' | 'closer', standing: Record<string, Way>,
) {
  const { Box, Text, Button } = $.ui.resolve(e)
  const width = Math.max(30, (e.viewport?.columns ?? 100) - INDENT - cells(BAR) - 2)
  const meta = SHOW_TIMING ? `(${MODEL} ${kind}${l.text ? ` ${(l.ms / 1000).toFixed(1)}s` : ''})` : ''
  const bar = <Text dimColor>{BAR}</Text>
  if (l.failed) {
    return (
      <Box paddingLeft={INDENT} flexDirection="row">
        {bar}
        <Text dimColor>🎭 {MODEL} {kind} failed: {l.failed}</Text>
      </Box>
    )
  }
  const base = kind === 'opener' ? 0 : 4
  const hasVotes = !!l.voteId
  // The terminal draws a Button as [ − ]. The vote standing on that part
  // draws its button bold in its color, + green and − red; the rest dim.
  const vote = (n: number, glyph: string) => {
    const slot = SLOTS[n]!
    const isCast = standing[`${l.voteId}:${kind}:${slot[0]}`] === slot[1]
    return (
      <Button key={`rv-${l.voteId}-${base + n}`} label={glyph} dimColor={!isCast} onPress={() => castVote($, l, kind, n)}>
        {isCast ? <Text bold color={slot[1] === 'up' ? 'success' : 'error'}>{glyph}</Text> : glyph}
      </Button>
    )
  }
  const sp = <Text> </Text>
  // The credit on one row when it fits, else the name and the universe each
  // start a row, so a narrow window splits it between them.
  // The emoji is the character's own, so it sits with the name.
  const who = `🎭 ${l.name} ${l.emoji}`
  const where = titleCase(l.universe)
  const head = cells(`${who} · ${where}`) <= width
    ? [`${who} · ${where}`]
    : [...wrapWords(who, width, width), ...wrapWords(where, width, width)]
  const body = l.text ? `"${l.text}"` : 'thinking…'
  const rows = wrapWords(meta ? `${body} ${meta}` : body, width, width)
  // Split the meta back off the last row so it can be drawn dim.
  const styled = (r: string, last: boolean) => {
    const at = last && meta ? r.lastIndexOf(meta) : -1
    const main = at >= 0 ? r.slice(0, at) : r
    return (
      <Text>
        <Text dimColor={!l.text}>{main}</Text>
        {at >= 0 ? <Text dimColor>{meta}</Text> : null}
      </Text>
    )
  }
  // The odds (random and universe mode), each dim before its own two buttons.
  const cOdds = l.odds ? pct(l.odds.c) : ''
  const uOdds = l.odds ? pct(l.odds.u) : ''
  const odds = (s: string) => (s ? <Text dimColor>{s} </Text> : null)
  return (
    <Box paddingLeft={INDENT} flexDirection="column">
      {head.map((r, i) => (
        <Box key={`h${i}`} flexDirection="row">
          {bar}
          <Text dimColor>{r}</Text>
        </Box>
      ))}
      {rows.map((r, i) => (
        <Box key={`r${i}`} flexDirection="row">
          {bar}
          {styled(r, i === rows.length - 1)}
        </Box>
      ))}
      {hasVotes || cOdds ? (
        <Box key="v" flexDirection="row">
          {bar}
          {odds(cOdds)}
          {hasVotes ? vote(2, '−') : null}
          {hasVotes ? sp : null}
          {hasVotes ? vote(1, '+') : null}
          <Text>{'   '}</Text>
          {odds(uOdds)}
          {hasVotes ? vote(4, '−') : null}
          {hasVotes ? sp : null}
          {hasVotes ? vote(3, '+') : null}
        </Box>
      ) : null}
    </Box>
  )
}
