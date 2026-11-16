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
// a vote (lib/lua/seeds/rolevote.lua) records only the vote id and slot, so
// that log is where a voted line is found again.
//
// Review: .cc/reports/REVIEW-roleplay-bookends-mod.md (2026-11-15).
import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'

import type { Line, VoteCount } from '../types'

const openers = atom({ plugin: 'roleplay-bookends', key: 'openers' } as const, {} as Record<string, Line>)
const closers = atom({ plugin: 'roleplay-bookends', key: 'closers' } as const, {} as Record<string, Line>)
const votes = atom({ plugin: 'roleplay-bookends', key: 'votes' } as const, { waiting: 0, old: 0 } as VoteCount)

// Vote reminder: a row above the prompt when more than VOTES_OLD votes have
// waited a week or more, or more than VOTES_MANY are waiting. Its button and
// link open a review session in a new iTerm tab (bin/rolevotes-review). The
// review writes votes-reviewed-at, which resets the count.
const VOTES_OLD = 3
const VOTES_MANY = 12
const WEEK_MS = 7 * 24 * 3600 * 1000
// Show the row whatever the count, to try the button and link.
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

const SYS =
  "You write one short in-character line for a character who bookends an AI coding assistant's replies to its user. " +
  "At most 25 words, in the character's own voice, about this specific work. " +
  'A plain status sentence with no character in it is a failure. ' +
  "Do not use jargon from the character's universe to describe the technical work. " +
  'Never repeat the example lines. Output only the line itself: no quotes, no name, no preamble.'

type Who = { name: string; emoji: string; universe: string; traits: string; extra: string; voteId?: string }

// One turn that got an opener: what its closer needs.
type Turn = { who: Who; prompt: string }

// [🎭 Character Roll: «Name» 🥷 UNIVERSE — traits || extra || vote id: x]
const WHO = /«([^»]+)»\s*(\S+)\s+(.+?)\s+—\s+([^|\]\n]+)((?:\|\|[^\]\n]*)?)/

function parseWho(s: string): Who | null {
  const m = WHO.exec(s)
  if (!m) return null
  const parts = (m[5] ?? '').split('||').map(x => x.trim())
  const voteId = parts.map(x => /^vote id: (\w+)$/.exec(x)?.[1]).find(Boolean)
  const extra = parts.filter(x => x && !x.startsWith('vote id')).join(' ')
  return { name: m[1]!.trim(), emoji: m[2]!, universe: m[3]!.trim(), traits: m[4]!.trim(), extra, ...(voteId ? { voteId } : {}) }
}

function norm(s: string): string {
  return s.replace(/\s+/g, ' ').trim()
}

// Opener rows are found by the prompt's start; closer rows by the answer's
// end, which is the end of its last text block, where the closer belongs.
function headKey(s: string): string {
  return norm(s).slice(0, 200)
}
function tailKey(s: string): string {
  return norm(s).slice(-200)
}

// The row shows a paste as "[Pasted text #1 +14 lines]" (or an image as
// "[Image #1]") while the prompt holds the pasted text, so the head key can
// miss. Then the row matches a stored prompt holding each typed piece around
// the placeholders, in order, starting with the first and ending with the last.
const PLACEHOLDER = /\[(?:Pasted text|Image) #\d+[^\]]*\]/
function findOpener(m: Record<string, Line>, shown: string): Line | undefined {
  const exact = m[headKey(shown)]
  if (exact || !PLACEHOLDER.test(shown)) return exact
  const parts = norm(shown).split(new RegExp(PLACEHOLDER.source, 'g')).map(p => p.trim())
  // A paste with no typed text around it matches every prompt: draw nothing
  // rather than repeat the newest opener under each such row.
  if (parts.every(p => !p)) return undefined
  const first = parts[0] ?? ''
  const last = parts[parts.length - 1] ?? ''
  const hits = Object.values(m).filter(l => {
    const full = l.prompt
    if (!full || !full.startsWith(first) || !full.endsWith(last)) return false
    let at = 0
    for (const p of parts) {
      if (!p) continue
      const i = full.indexOf(p, at)
      if (i < 0) return false
      at = i + p.length
    }
    return true
  })
  return hits[hits.length - 1]
}

// Module state: lost on a reload; reset on /clear by session.end.
let examples = ''
let lastAnswer = ''
// Typed prompts seen at submit, oldest first, waiting for their turn.
let queue: { text: string; at: number }[] = []
// Turns that got an opener, by turn id.
const turns = new Map<string, Turn>()
// Vote ids already given to a turn, so one roll is never used twice.
const usedVotes = new Set<string>()

function resetSession() {
  lastAnswer = ''
  queue = []
  turns.clear()
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
  return { name: w.name, emoji: w.emoji, universe: w.universe, text: null, ms: 0, ...(w.voteId ? { voteId: w.voteId } : {}) }
}

// Sets one row and drops the oldest past KEEP, so the maps (and the rows
// that read them) stay small in a long session.
function withRow(m: Record<string, Line>, key: string, line: Line): Record<string, Line> {
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
      const sig = f[4] ?? ''
      const extra = !sig
        ? ''
        : Math.random() < 1 / 3
          ? `Signature line unlocked this time: you may use ${sig}.`
          : `Signature line spent this time: do not use ${sig}; use a less-worn part of the character.`
      return { name, emoji: f[2]!, universe, traits: f[3]!, extra, voteId }
    }
  }
  return null
}

// The mod's own roll. --votes logs it and puts a vote id in the tag, so the
// vote links work as the hook's did. Its output is the hook's JSON envelope.
async function ownRoll($: EngineInterface): Promise<Who | null> {
  const r = await $.process.run(['sh', '-c', '"$HOME/dotfiles/roleplay/bin/roleplay-roll" --votes'], { timeoutMs: 5000 })
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
  $: EngineInterface, kind: 'opener' | 'closer', key: string, w: Who, ask: string, turnId: string, prompt?: string,
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
  const line: Line = { ...pendingLine(w), text, ms, ...(failed ? { failed } : {}), ...(prompt ? { prompt } : {}) }
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

async function startOpener($: EngineInterface, turnId: string, text: string, submittedAt: number) {
  let w = HOOK_ROLLS ? await hookRoll($, submittedAt) : null
  const via = w ? 'hook roll' : 'own roll'
  if (!w) w = await ownRoll($)
  await dbg($, `opener ${turnId} who=${w ? w.name : 'none'} via=${via}`)
  if (!w) return
  if (w.voteId) usedVotes.add(w.voteId)
  turns.set(turnId, { who: w, prompt: text })
  const key = headKey(text)
  const full = norm(text).slice(0, 20000)
  await setRow($, 'opener', key, { ...pendingLine(w), prompt: full })
  const ask =
    `Character: ${w.name} (${w.universe}) — ${w.traits}${w.extra ? `\nNote: ${w.extra}` : ''}\n` +
    exampleBlock(w.name) +
    (lastAnswer ? `\nThe assistant's previous reply ended:\n${lastAnswer.slice(-1500)}\n` : '') +
    `\nThe user just asked:\n${text.slice(-3000)}\n\n` +
    'Write the OPENER: the line at the top of the reply, reacting to this request as the work begins.'
  await write($, 'opener', key, w, ask, turnId, full)
}

async function startCloser($: EngineInterface, turnId: string, t: Turn, answerText: string) {
  const w = t.who
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
  on('session.start', async ($, e, next) => {
    const r = await $.process.run(['sh', '-c', 'cat "$HOME/dotfiles/roleplay/examples.md"'], { timeoutMs: 5000 })
    examples = r.exitCode === 0 ? r.stdout : ''
    // A reload kills calls in flight; their rows would say "thinking" forever.
    const stale = (m: Record<string, Line>) =>
      Object.fromEntries(Object.entries(m).map(([k, l]) => [k, l.text || l.failed ? l : { ...l, failed: 'cut off by a mod reload' }]))
    await update($, openers, stale)
    await update($, closers, stale)
    $.clock.after(0, () => countVotes($).catch(err => dbg($, `vote count error ${String(err)}`)))
    return next(e)
  })

  // /clear ends the session in-process with no new session.start.
  on('session.end', async ($, e, next) => {
    resetSession()
    return next(e)
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
    const text = norm(e.text)
    const i = queue.findIndex(q => text === norm(q.text) || text.includes(norm(q.text)))
    if (i < 0) return next(e)
    const q = queue[i]!
    // Older entries never started a turn (folded into a running one): drop them.
    queue = queue.slice(i + 1)
    const turnId = e.turnId
    $.clock.after(0, () =>
      startOpener($, turnId, q.text, q.at).catch(err => dbg($, `opener error ${turnId} ${String(err)}`)),
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

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    const v = await read($, votes)
    const due = v.old > VOTES_OLD || v.waiting > VOTES_MANY
    if (e.props.hasSurvey || (!due && !VOTES_DEMO)) return next(e)
    const { Box, Text, Button, Link } = $.ui.resolve(e)
    const what = v.old > VOTES_OLD ? `${v.waiting} roleplay votes waiting, ${v.old} over a week old` : `${v.waiting} roleplay votes waiting`
    return (
      <Box flexDirection="row" columnGap={1}>
        <Text>🎭 {what}{due ? '' : ' (demo)'}</Text>
        <Button
          key="rolevotes"
          label="Review"
          onPress={() => {
            void $.process.run(['sh', '-c', '"$HOME/dotfiles/bin/rolevotes-review"'], { timeoutMs: 15000 })
          }}
        />
        <Link href="hammerspoon://rolevotes" label="open review" />
      </Box>
    )
  })

  on('ui.render', { component: 'UserMessage' }, async ($, e, next) => {
    const inner = await next(e)
    const l = findOpener(await read($, openers), e.props.text)
    if (!l) return inner
    const { Box } = $.ui.resolve(e)
    return (
      <Box flexDirection="column">
        {inner}
        <Box marginTop={1}>{bookend($, e, l, 'opener')}</Box>
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
        <Box marginTop={1}>{bookend($, e, l, 'closer')}</Box>
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

// One bookend, drawn like a blockquote in the reply: indented to the reply's
// text, a dim bar on every row, then
// 🎭 «Name» [−][+] emoji UNIVERSE [−][+] — "line"   (model kind 1.2s)
// Rows are wrapped by hand so the bar runs down each one. The vote links are
// roleplay-roll's: vote id + 1–4 on the opener, 5–8 on the closer, numbered
// character +, character −, universe +, universe −; drawn minus first.
const INDENT = 2
const BAR = '▎ '
function bookend($: EngineInterface, e: Parameters<EngineInterface['ui']['resolve']>[0] & { viewport?: { columns: number } }, l: Line, kind: 'opener' | 'closer') {
  const { Box, Text, Link } = $.ui.resolve(e)
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
  const vote = (n: number, glyph: string) => (
    <Link key={`v${n}`} href={`hammerspoon://r?v=${l.voteId}${base + n}`} label={` ${glyph} `} />
  )
  const sp = <Text> </Text>
  // Head: 🎭 «Name» [ − ] [ + ] emoji UNIVERSE [ − ] [ + ] — , single spaces
  // between parts; each vote link is 3 cells plus its space.
  const head = cells(`🎭 «${l.name}» ${l.emoji} ${l.universe} — `) + (hasVotes ? 4 * 4 : 0)
  const body = l.text ? `"${l.text}"` : 'thinking…'
  const words = meta ? `${body} ${meta}` : body
  const rows = wrapWords(words, Math.max(0, width - head), width)
  // Split the meta back off the last row so it can be drawn dim.
  const styled = (row: string, last: boolean) => {
    const at = last && meta ? row.lastIndexOf(meta) : -1
    const main = at >= 0 ? row.slice(0, at) : row
    return (
      <Text>
        <Text italic dimColor={!l.text}>{main}</Text>
        {at >= 0 ? <Text dimColor>{meta}</Text> : null}
      </Text>
    )
  }
  const firstFits = rows[0] !== undefined && cells(rows[0]) <= width - head
  const firstRow = firstFits ? rows.shift() : undefined
  return (
    <Box paddingLeft={INDENT} flexDirection="column">
      <Box flexDirection="row">
        {bar}
        <Text>🎭 </Text>
        <Text bold italic>«{l.name}»</Text>
        {sp}
        {hasVotes ? vote(2, '−') : null}
        {hasVotes ? sp : null}
        {hasVotes ? vote(1, '+') : null}
        {hasVotes ? sp : null}
        <Text>{l.emoji} </Text>
        <Text italic color="permission">{l.universe}</Text>
        {sp}
        {hasVotes ? vote(4, '−') : null}
        {hasVotes ? sp : null}
        {hasVotes ? vote(3, '+') : null}
        {hasVotes ? sp : null}
        <Text>— </Text>
        {firstRow !== undefined ? styled(firstRow, rows.length === 0) : null}
      </Box>
      {rows.map((r, i) => (
        <Box key={`r${i}`} flexDirection="row">
          {bar}
          {styled(r, i === rows.length - 1)}
        </Box>
      ))}
    </Box>
  )
}
