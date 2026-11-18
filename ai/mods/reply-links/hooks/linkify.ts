// Split a reply into markdown and rows of answer buttons, and turn its
// question labels and Where-next IDs into links a click answers.
//
// Buttons come only from an answer line, which the model writes because the
// mod's own system-prompt section (RULE in register.tsx) asks it to:
//
//   - **Q4 (commit):** Commit these changes?
//     【Q4: yes* | no】                     answers split by "|"; "*" marks
//                                           the one recommended. The line
//                                           must stand alone. Drawn as a row
//                                           of buttons in its place.
//
// A click fills "Q4 (commit): yes": the label is looked up by its ID in the
// reply. Nothing is guessed from the question's wording; a question with no
// answer line gets no buttons. Small slips still parse: a full-width ：or ｜,
// a bullet or number before the line, bold or backticks around an answer.
// A line left with no answers is dropped, never drawn raw.
//
// The row sits at the answer line's own indent, else at its question's (the
// last line above that holds that ID's label), so a row after a block
// question's answer bullets lines up with the question, not the last bullet.
//
// Also, by fixed shapes the reply format (~/.claude/CLAUDE.md) writes:
//   **Q4 (commit)**                         a bold question label: a link
//                                           that fills "Q4 (commit): "
//   🧭 **Where next:**
//   - N3 💡 Try the inline version          a Where-next item, only in that
//                                           list: its ID is drawn as a filled
//                                           button, "[ N3 ]", that fills its
//                                           text. An indented line after it
//                                           wraps on with the item.
//
// Links get a placeholder https address (Markdown draws only https, http and
// file links). The mod answers a plain click on one itself, so the address
// never opens. hammerspoon:// links (copy, rolevote) would draw as plain text
// in a mod's Markdown, so they get a placeholder too, and a click opens the
// real URL. Nothing inside a code fence or a `code span` is changed or read.

export type Action = { kind: 'fill'; text: string } | { kind: 'open'; url: string }

export type Answer = { label: string; text: string; isPrimary: boolean }

export type Segment =
  | { kind: 'markdown'; text: string; hrefs: string[] }
  | { kind: 'buttons'; answers: Answer[]; indent: number }
  // A Where-next item: `lead` is its bullet ("- "), `mark` its 💡 or 🔮,
  // `href` the key of its fill action, `rest` the markdown after the ID.
  | { kind: 'item'; indent: number; lead: string; mark: string; id: string; href: string; rest: string; hrefs: string[] }

export type Linked = { segments: Segment[]; actions: Map<string, Action> }

const BASE = 'https://reply-links.invalid/'

// Under the 256 links one Markdown element may answer, with room for a line.
const MAX_LINKS = 200

// A label's parentheses may hold one level of their own: "Q4 (turn on (beta))".
const PARENS = String.raw`\((?:[^()]|\([^()]*\))*\)`
const LEAD = String.raw`(?:[-*]|\d+[.)])\s+`

const ANSWER_LINE = new RegExp(String.raw`^(\s*)(?:${LEAD})?【\s*(Q\d+)\s*[:：]\s*([^【】]*?)\s*】\s*$`)
const Q_BOLD = new RegExp(String.raw`\*\*(Q\d+ ${PARENS})(:?)\*\*`, 'g')
const Q_BOLD_ID = new RegExp(String.raw`\*\*((Q\d+) ${PARENS})`, 'g')
const Q_LABEL_ID = new RegExp(String.raw`\b((Q\d+) ${PARENS})`, 'g')
const Q_LINE = new RegExp(String.raw`^(\s*(?:${LEAD})?)(👀\s*\*\*Needs you:\*\*\s*)?\*\*(Q\d+) ${PARENS}`, 'u')
const N_ITEM = /^(\s*[-*]\s+(?:(?:💡|🔮)\s*)?)(N\d+)\b(.*)$/u
const WHERE_NEXT = /\*\*Where next:?\*\*/
const HS_LINK = /\]\((hammerspoon:\/\/[^)\s]+)\)/g
const FENCE_OPEN = /^\s*(`{3,}|~{3,})/
const BULLET = /^\s*[-*]\s/

/**
 * The line cut into text and code spans, alternating, text first. A span
 * opens on a run of backticks and closes on a run of the same length, as
 * CommonMark has it; an unclosed run is text.
 */
function codeSplit(line: string): string[] {
  const parts: string[] = []
  let text = ''
  let i = 0
  while (i < line.length) {
    if (line[i] !== '`') {
      text += line[i]
      i++
      continue
    }
    let j = i
    while (line[j] === '`') j++
    const run = line.slice(i, j)
    let k = j
    let close = -1
    while (k < line.length) {
      if (line[k] !== '`') {
        k++
        continue
      }
      let m = k
      while (line[m] === '`') m++
      if (m - k === run.length) {
        close = m
        break
      }
      k = m
    }
    if (close < 0) {
      text += run
      i = j
      continue
    }
    parts.push(text, line.slice(i, close))
    text = ''
    i = close
  }
  parts.push(text)
  return parts
}

/** Applies `fn` to the parts of `line` outside code spans. */
function outsideCode(line: string, fn: (part: string) => string): string {
  return codeSplit(line)
    .map((p, i) => (i % 2 === 1 ? p : fn(p)))
    .join('')
}

/** The lines outside code fences, with code spans cut out. */
function proseLines(src: string): string[] {
  const out: string[] = []
  let fence: { char: string; len: number } | null = null
  for (const line of src.split('\n')) {
    const f = FENCE_OPEN.exec(line)?.[1]
    if (fence) {
      if (f && f[0] === fence.char && f.length >= fence.len && /^\s*[`~]+\s*$/.test(line)) fence = null
      continue
    }
    if (f) {
      fence = { char: f[0] ?? '`', len: f.length }
      continue
    }
    out.push(codeSplit(line).filter((_, i) => i % 2 === 0).join(''))
  }
  return out
}

/** "Q4" → "Q4 (commit)": a bold label first, else any, outside code. */
function labels(src: string): Map<string, string> {
  const prose = proseLines(src).join('\n')
  const found = new Map<string, string>()
  for (const re of [Q_BOLD_ID, Q_LABEL_ID]) {
    for (const m of prose.matchAll(re)) {
      const [, whole = '', id = ''] = m
      if (!found.has(id)) found.set(id, whole)
    }
  }
  return found
}

/** The answers of an answer line's body: "yes* | no". */
export function parseAnswers(body: string, label: string): Answer[] {
  return body
    .split(/[|｜]/)
    .map(raw => {
      let s = raw.trim().replace(/\*\*([^*]+)\*\*/g, '$1')
      const isPrimary = /\*$/.test(s)
      s = s.replace(/^[*\s]+|[*\s]+$/g, '').replace(/`/g, '').trim()
      return { label: s, text: `${label}: ${s}`, isPrimary }
    })
    .filter(a => a.label !== '')
}

export function linkify(src: string): Linked {
  const actions = new Map<string, Action>()
  const add = (a: Action): string => {
    const href = `${BASE}${actions.size}`
    actions.set(href, a)
    return href
  }

  const segments: Segment[] = []
  let md: string[] = []
  let hrefs: string[] = []
  const flush = () => {
    // Blank lines at a cut would only add space around the buttons.
    while (md.length > 0 && md[md.length - 1]?.trim() === '') md.pop()
    while (md.length > 0 && md[0]?.trim() === '') md.shift()
    if (md.length > 0) segments.push({ kind: 'markdown', text: md.join('\n'), hrefs })
    md = []
    hrefs = []
  }
  const link = (a: Action) => {
    const href = add(a)
    hrefs.push(href)
    return href
  }
  const links = (s: string) =>
    outsideCode(s, part =>
      part
        .replace(HS_LINK, (_, url: string) => `](${link({ kind: 'open', url })})`)
        .replace(Q_BOLD, (_, q: string, colon: string) =>
          `**[${q}](${link({ kind: 'fill', text: `${q}: ` })})${colon}**`,
        ),
    )

  const label = labels(src)
  const questionIndent = new Map<string, number>()
  let fence: { char: string; len: number } | null = null
  let inWhereNext = false

  for (const line of src.split('\n')) {
    const f = FENCE_OPEN.exec(line)?.[1]
    if (fence) {
      // A closing fence is its marker alone: "```js" inside does not close.
      if (f && f[0] === fence.char && f.length >= fence.len && /^\s*[`~]+\s*$/.test(line)) fence = null
      md.push(line)
      continue
    }
    if (f) {
      fence = { char: f[0] ?? '`', len: f.length }
      md.push(line)
      continue
    }

    const a = ANSWER_LINE.exec(line)
    if (a) {
      const [, own = '', id = '', body = ''] = a
      const answers = parseAnswers(body, label.get(id) ?? id)
      if (answers.length > 0) {
        flush()
        segments.push({ kind: 'buttons', answers, indent: own.length || (questionIndent.get(id) ?? 0) })
      }
      continue
    }

    const q = Q_LINE.exec(line)
    if (q) questionIndent.set(q[3] ?? '', q[2] ? 0 : (q[1]?.length ?? 0))

    if (WHERE_NEXT.test(line)) inWhereNext = true
    else if (/^\s*(⏳|👀)/u.test(line)) inWhereNext = false
    // A line at the margin that is not a bullet ends the list; an indented
    // one continues the item above.
    else if (line.trim() !== '' && !BULLET.test(line) && !/^\s/.test(line)) inWhereNext = false

    const n = inWhereNext ? N_ITEM.exec(line) : null
    if (n) {
      const [, lead = '', id = '', rest = ''] = n
      const shown = rest.replace(/^[\s:.—–-]+/, '')
      const prompt = shown
        .replace(/^(?:💡|🔮)\s*/u, '')
        .replace(/\*\*/g, '')
        .trim()
      flush()
      const bullet = /^(\s*)([-*])\s+(?:(💡|🔮)\s*)?$/u.exec(lead)
      const href = add({ kind: 'fill', text: prompt || id })
      // The item's own links: `links` pushes onto `hrefs`, so take them off.
      const text = links(shown)
      segments.push({
        kind: 'item',
        indent: bullet?.[1]?.length ?? 0,
        lead: `${bullet?.[2] ?? '-'} `,
        mark: bullet?.[3] ?? '',
        id,
        href,
        rest: text,
        hrefs,
      })
      hrefs = []
      continue
    }

    // An indented line right after an item wraps on with it.
    const last = segments[segments.length - 1]
    if (inWhereNext && md.length === 0 && last?.kind === 'item' && /^\s+\S/.test(line)) {
      last.rest = `${last.rest} ${links(line.trim())}`.trim()
      last.hrefs.push(...hrefs)
      hrefs = []
      continue
    }

    md.push(links(line))
    // A Markdown element answers at most 256 links: cut a long run early.
    if (hrefs.length >= MAX_LINKS) flush()
  }
  flush()

  return { segments, actions }
}

/** True when the reply holds nothing for the mod to draw. */
export function isPlain(l: Linked): boolean {
  return l.actions.size === 0 && l.segments.every(s => s.kind === 'markdown')
}

const ANSWER_KEY = new RegExp(String.raw`^(Q\d+(?: ${PARENS})?): `)

/**
 * What the prompt box holds after a press adds `text` to `box`, line by line:
 * - an answer ("Q4 (commit): yes") replaces the line of an earlier answer to
 *   the same question, or the bare label a label link left ("Q4 (commit): ");
 * - a line the box already holds is not added again;
 * - else the text goes on a line of its own after the draft.
 */
export function addToBox(box: string, text: string): string {
  if (box.trim() === '') return text
  const lines = box.split('\n')
  const key = ANSWER_KEY.exec(text)?.[1]
  if (key) {
    const at = lines.findIndex(l => l.startsWith(`${key}: `) || l.trimEnd() === `${key}:`)
    if (at >= 0) {
      // A bare label never wipes an answer already given.
      if (text.trimEnd() === `${key}:`) return box
      lines[at] = text
      return lines.join('\n')
    }
  }
  if (lines.some(l => l.trim() === text.trim())) return box
  return box + (box.endsWith('\n') ? '' : '\n') + text
}
