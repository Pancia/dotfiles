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
//                                           button, "[ N3 ]", that fills the
//                                           bare ID, "N3". An indented line after it
//                                           wraps on with the item.
//
// Links get a placeholder https address (Markdown draws only https, http and
// file links). The mod answers a plain click on one itself, so the address
// never opens. hammerspoon:// links (copy, rolevote) would draw as plain text
// in a mod's Markdown, so they get a placeholder too, and a click opens the
// real URL. Nothing inside a code fence or a `code span` is changed or read,
// with one exception below.
//
// A slash command the session knows ("/cc:retro", in prose or as a whole
// `code span`, with or without arguments) gets a button in a row under the
// paragraph or list that names it; the text itself is left as written. A
// block ends at a blank line, a fence, an answer line or the end. A click
// fills the box with the command, so Enter runs it. The caller passes the
// names it knows; with none, there is no row, so "/usr/bin" gets no button.

export type Action =
  | { kind: 'fill'; text: string }
  | { kind: 'open'; url: string }
  // A slash command, "/cc:retro args": it must start the box to run.
  | { kind: 'command'; text: string }

export type Answer = { label: string; text: string; isPrimary: boolean }

export type Segment =
  | { kind: 'markdown'; text: string; hrefs: string[] }
  | { kind: 'buttons'; answers: Answer[]; indent: number }
  // A Where-next item: `lead` is its bullet ("- "), `mark` its 💡 or 🔮,
  // `href` the key of its fill action, `rest` the markdown after the ID.
  | { kind: 'item'; indent: number; lead: string; mark: string; id: string; href: string; rest: string; hrefs: string[] }
  // The slash commands of the paragraph or list above, as "/cc:retro".
  | { kind: 'commands'; commands: string[]; indent: number }

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

// A command name: "clear", "cc:retro", "code-review".
const CMD_NAME = String.raw`[A-Za-z][\w-]*(?::[\w-]+)*`
// In prose: "/clear", maybe after "*" or "_" (bold, italic), and before the
// end, a space or punctuation; a "." or ":" only before a space or the end, so
// "/config.json" is no command. What may come before it is checked in
// `prose`: the line's start, a space, or a "(" that opens no link target.
const CMD_PROSE = new RegExp(String.raw`(\*{1,3}|_{1,3})?/(${CMD_NAME})(?=$|[\s,;!?)*_]|[.:](?=\s|$))`, 'g')
const LIST_MARK = /^\s*(?:[-*+]|\d+[.)])\s/
const ITEM_TEXT = /^\s*(?:[-*+]|\d+[.)])\s+/
const HEADING = /^\s{0,3}#{1,6}\s/
const END_LINE = /^\s*(⏳|👀)/u
// Lines whose text is not prose: a reference definition, a block quote.
const NOT_PROSE = /^\s{0,3}(?:\[[^\]]+\]:\s|>)/
// A whole code span: "`/cc:retro`" or "`/code-review high`".
const CMD_SPAN = new RegExp(String.raw`^(\`+)\s?/(${CMD_NAME})((?:\s[^\`]*)?)\s?\1$`)

/**
 * True when `src` may hold a slash command: worth asking for the names. Any
 * "/" before a letter, so it never misses one; the names are cached.
 */
export function mayHaveCommand(src: string): boolean {
  return /\/[A-Za-z]/.test(src)
}

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

export function linkify(src: string, commands: ReadonlySet<string> = new Set()): Linked {
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
  // The commands named since the last row of them, each once, in order.
  let pending: string[] = []
  const command = (text: string) => {
    if (!pending.includes(text)) pending.push(text)
  }
  // `first`: the part opens the line, so its start is the line's start.
  const prose = (part: string, first: boolean, scan: boolean) => {
    const out = part
      .replace(HS_LINK, (_, url: string) => `](${link({ kind: 'open', url })})`)
      .replace(Q_BOLD, (_, q: string, colon: string) =>
        `**[${q}](${link({ kind: 'fill', text: `${q}: ` })})${colon}**`,
      )
    // The text is left as written; the command only joins the row.
    if (scan && commands.size > 0) {
      for (const m of part.matchAll(CMD_PROSE)) {
        const at = m.index ?? 0
        const before = part[at - 1]
        const opens =
          before === undefined
            ? first
            : /\s/.test(before) || (before === '(' && part[at - 2] !== ']')
        // A name may hold "_", so "_/x_" takes the closing "_" into it.
        const lead = m[1] ?? ''
        const name = lead.startsWith('_') ? (m[2] ?? '').replace(/_+$/, '') : (m[2] ?? '')
        // "**/x**" is bold; "**/x" with no closing run is a glob.
        const closed = lead === '' || part.startsWith(lead, at + lead.length + 1 + name.length)
        if (opens && closed && commands.has(name)) command(`/${name}`)
      }
    }
    return out
  }
  const span = (code: string, scan: boolean) => {
    const m = scan && commands.size > 0 ? CMD_SPAN.exec(code) : null
    if (m && commands.has(m[2] ?? '')) command(`/${m[2]}${(m[3] ?? '').trimEnd()}`)
    return code
  }
  const links = (s: string, scan = true) =>
    codeSplit(s)
      .map((p, i) => (i % 2 === 1 ? span(p, scan) : prose(p, i === 0, scan)))
      .join('')
  // The row of command buttons under the paragraph or list that named them.
  let blockIndent = 0
  const commandRow = () => {
    if (pending.length === 0) return
    flush()
    segments.push({ kind: 'commands', commands: pending, indent: blockIndent })
    pending = []
  }

  const label = labels(src)
  const questionIndent = new Map<string, number>()
  let fence: { char: string; len: number; margin: boolean } | null = null
  let inWhereNext = false

  // Where a block ends, so its row goes in: never inside a list item, where a
  // cut would split the item's Markdown and draw its rest as code. A block
  // ends before a blank line's next text at the margin that is no list item,
  // a margin fence, a heading, the Where-next line, the "⏳"/"👀" lines; after
  // a heading, a margin fence or an answer line; and at the end.
  let atStart = true
  let prevBlank = false
  let cutNext = false
  let fenceEnded = false
  let blockIsList = false
  // The column where the last list item's text starts: "  - x" → 4.
  let itemText = 0
  let inIndentedCode = false
  let inComment = false

  for (const line of src.split('\n')) {
    const f = FENCE_OPEN.exec(line)?.[1]
    if (fence) {
      // A closing fence is its marker alone: "```js" inside does not close.
      if (f && f[0] === fence.char && f.length >= fence.len && /^\s*[`~]+\s*$/.test(line)) {
        if (fence.margin) cutNext = true
        else fenceEnded = true
        fence = null
      }
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
      // The question's commands go under its answers, not between them.
      commandRow()
      cutNext = true
      prevBlank = false
      continue
    }

    const blank = line.trim() === ''
    if (!blank) {
      const indent = /^\s*/.exec(line)?.[0].length ?? 0
      const cut =
        atStart ||
        cutNext ||
        END_LINE.test(line) ||
        WHERE_NEXT.test(line) ||
        HEADING.test(line) ||
        (f !== undefined && indent === 0) ||
        // Text at the margin after a list item's fence is no lazy line of it.
        (fenceEnded && indent === 0 && !LIST_MARK.test(line)) ||
        (prevBlank && !(blockIsList && (LIST_MARK.test(line) || indent > 0)))
      if (cut) {
        commandRow()
        blockIndent = indent
        blockIsList = false
      }
      // Four spaces past where text may start open an indented code block:
      // outside a list after a blank line or at a block's start (the reply's,
      // a heading's, a fence's); in a list item, four past the item's text,
      // after a blank line.
      inIndentedCode = blockIsList
        ? indent >= itemText + 4 && (prevBlank || inIndentedCode)
        : indent >= 4 && (prevBlank || inIndentedCode || cut)
      const mark = inIndentedCode ? null : ITEM_TEXT.exec(line)
      if (mark) {
        blockIsList = true
        itemText = mark[0].length
      }
      cutNext = HEADING.test(line)
      fenceEnded = false
      atStart = false
    }
    prevBlank = blank
    // Nothing in an HTML comment is prose: "<!-- /clear -->".
    const commented = inComment || line.includes('<!--')
    if (line.lastIndexOf('<!--') > line.lastIndexOf('-->')) inComment = true
    else if (line.includes('-->')) inComment = false
    const scan = !inIndentedCode && !commented && !NOT_PROSE.test(line)

    if (f) {
      fence = { char: f[0] ?? '`', len: f.length, margin: /^[`~]/.test(line) }
      md.push(line)
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
      flush()
      const bullet = /^(\s*)([-*])\s+(?:(💡|🔮)\s*)?$/u.exec(lead)
      // The bare ID: a reply of only "N3" is taken as that item's prompt.
      const href = add({ kind: 'fill', text: id })
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

    md.push(links(line, scan))
    // A Markdown element answers at most 256 links: cut a long run early.
    if (hrefs.length >= MAX_LINKS) flush()
  }
  commandRow()
  flush()

  return { segments, actions }
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

/**
 * True when the box holds only a slash command a click could have put there:
 * a known name with nothing after it, or one of the reply's own commands
 * (`offered`, arguments and all). A path or a command the person typed with
 * words of their own is a draft.
 */
export function isLoneCommand(box: string, commands: ReadonlySet<string>, offered: readonly string[]): boolean {
  const t = box.trim()
  if (offered.includes(t)) return true
  const m = new RegExp(String.raw`^/(${CMD_NAME})$`).exec(t)
  return m !== null && commands.has(m[1] ?? '')
}

/**
 * What the prompt box holds after a press puts the slash command `text` in
 * `box`, or null when it cannot go in: a command runs only from the start of
 * the box, so it takes an empty box, or replaces a lone command (an earlier
 * click). A draft of the person's own is never touched.
 */
export function commandToBox(
  box: string,
  text: string,
  commands: ReadonlySet<string>,
  offered: readonly string[],
): string | null {
  if (box.trim() === '' || isLoneCommand(box, commands, offered)) return text
  return null
}
