// reply-links: in a reply, question labels and Where-next IDs become links,
// and an answer line under a question (【Q4: yes* | no】, which RULE below
// teaches the model) becomes a row of buttons. A click puts that text in the
// prompt box. It never sends.
//
// Only the drawing changes: the stored reply, and what the model reads, stay
// as written. A click is answered by the mod only in the fullscreen terminal;
// a cmd-click on a link there opens its placeholder address.

import type { Register } from 'claude-code'

import { addToBox, isPlain, linkify } from './linkify'
import type { Action } from './linkify'

const SECTION = 'reply-links:answer-buttons'

// Drawn dim at the start of each row of answer buttons.
const PREFIX = '↳ 💬'

// The system-prompt section that asks for answer lines: about 250 tokens,
// once per session (after the cache boundary, so cached across its turns).
// Each answer line then costs about 10 output tokens; 【 and 】 are one token
// each on Opus 5.5 (measured 2026-11-17).
const RULE = `# Answer buttons

When a reply asks the user a question that has an ID (such as Q4) and a short, fixed set of answers, write an answer line for it:

【Q4: yes* | no】

- Put it on a line of its own, not as a bullet, indented like the question's text. For a one-line question, put it on the next line. For a question with answer bullets, put it after the last bullet.
- Write the question's ID, a colon, then the answers separated by "|". Write each answer as the user would type it: a word or a short label such as yes, no, A, B or keep. An answer never holds "|".
- Put "*" after the answer you recommend. Leave it out when you recommend none.
- When a still-open question is listed again, add its answer line again under that line. The answer line does not count as a second line for that question.
- Leave it out for a question with no ID, or one that needs free text.
- Outside code, never use 【 or 】 for anything else.

The terminal draws the line as clickable buttons. A click puts "Q4 (label): answer" in the user's prompt box.`

export const register: Register = on => {
  // Teach the answer line only where this mod draws it: an interactive
  // terminal session, not -p runs, teammates, or a session that speaks to
  // the person through a message tool (whose text this mod never draws).
  // Compose has no fullscreen fact, so the main screen still gets the rule;
  // the user's settings run fullscreen. A fork subagent copies the prompt,
  // so it carries the rule too; nothing here tells it apart.
  on('prompt.compose', async ($, e, next) => {
    const result = await next(e)
    const draws = e.surfaces.includes('terminal')
    const skip = e.traits.some(t => t === 'print' || t === 'teammate' || t === 'bare' || t === 'send-user-message')
    if (!draws || skip || result.sections.some(x => x.id === SECTION)) return result
    return { sections: [...result.sections, { id: SECTION, text: RULE, scope: 'session' as const }] }
  })

  on('ui.render', { component: 'AssistantMessage' }, async ($, e, next) => {
    // Clicks reach the mod only in the fullscreen terminal; elsewhere the
    // engine's own drawing keeps the hammerspoon links working.
    if (e.surface !== 'terminal' || e.props.isSummary || e.viewport?.isFullscreen === false) {
      return next(e)
    }

    // Cheap check first: a reply with nothing to draw goes on untouched.
    const quick = linkify(e.props.text)
    if (isPlain(quick)) return next(e)

    // Run the plugins beneath first, then put our drawing where the engine's
    // own node is in what they returned, so a wrapper beneath (the roleplay
    // closer) keeps its part. The chain order between mods is not documented,
    // so this works in either order. No engine node, or several, means a
    // plugin beneath drew the reply its own way: keep that.
    const inner = await next(e)
    if (countEngine(inner) !== 1) return inner

    // Draw the props the engine node would have drawn: a plugin beneath may
    // have rewritten them on the way down. The engine's trace entry holds
    // them; without one, our own props.
    const core = next.trace.find(t => t.plugin === 'engine')?.received
    const props = core?.component === 'AssistantMessage' && typeof core.props.text === 'string' ? core.props : e.props
    const linked = props.text === e.props.text ? quick : linkify(props.text)
    if (isPlain(linked)) return inner

    const { Box, Text, Markdown, Button } = $.ui.resolve(e)

    const run = async (action: Action | undefined) => {
      if (!action) return
      if (action.kind === 'open') {
        try {
          const { exitCode, stderr } = await $.process.run(['open', action.url])
          if (exitCode !== 0) $.ui.toast(`Could not open the link: ${stderr.trim() || `exit ${exitCode}`}`)
        } catch (err) {
          $.ui.toast(`Could not open the link: ${String(err)}`)
        }
        return
      }
      try {
        const box = await $.prompt.read()
        const text = addToBox(box.text, action.text)
        if (text === box.text) return
        // Append when only text is added, so a draft the read did not see
        // (it answers '' before the box is mounted) is never replaced.
        const filled = text.startsWith(box.text)
          ? await $.prompt.fill({ text: text.slice(box.text.length), mode: 'append' })
          : await $.prompt.fill({ text })
        if (!filled.isFilled) {
          $.ui.toast(filled.refusal === 'dialog' ? 'Close the dialog first, then click again.' : 'The prompt box did not take the text.')
        }
      } catch (err) {
        $.ui.toast(`Could not fill the prompt box: ${String(err)}`)
      }
    }

    const parts = linked.segments.map((s, i) =>
      s.kind === 'markdown' ? (
        <Markdown
          key={`md${i}`}
          text={s.text}
          onLinkPress={link => run(linked.actions.get(link.href))}
          pressableLinks={s.hrefs}
        />
      ) : (
        // Right under its question; one blank row only when more text follows.
        <Box
          key={`row${i}`}
          flexDirection="row"
          flexWrap="wrap"
          marginLeft={s.indent}
          marginBottom={i < linked.segments.length - 1 ? 1 : 0}
        >
          <Box key={`lead${i}`} marginRight={1}>
            <Text dimColor>{PREFIX}</Text>
          </Box>
          {s.answers.map((a, j) => (
            <Box key={`cell${i}-${j}`} marginRight={2}>
              {/* "[ yes ]" filled, as a Button looks under the pointer. The
                  fill is a background color, not `inverse`: the pointer's own
                  inversion sets `inverse` too, so on an inverse run it changed
                  nothing, and a `hover` override lost to it. The recommended
                  answer is filled in Claude's orange. `plain` so the engine
                  adds no brackets of its own. */}
              <Button
                key={`b${i}-${j}`}
                label={a.label}
                plain
                onPress={() => run({ kind: 'fill', text: a.text })}
              >
                <Text
                  backgroundColor={a.isPrimary ? 'claude' : 'text'}
                  color="inverseText"
                  bold={a.isPrimary}
                >
                  {`[ ${a.label} ]`}
                </Text>
              </Button>
            </Box>
          ))}
        </Box>
      ),
    )

    const mine = (
      <Box flexDirection="row">
        <Box width={2} flexShrink={0}>
          <Text>{props.isFirstOfReply ? '⏺' : ' '}</Text>
        </Box>
        <Box flexDirection="column" flexGrow={1} flexShrink={1}>
          {parts}
        </Box>
      </Box>
    )
    return swapEngine(inner, mine)
  })
}

type Node = { type?: unknown; children?: unknown }

const isEngine = (n: unknown): boolean =>
  typeof n === 'object' && n !== null && (n as Node).type === 'engine'

/** How many of the engine's own `{ type: 'engine' }` nodes the tree holds. */
function countEngine(n: unknown): number {
  if (isEngine(n)) return 1
  if (typeof n !== 'object' || n === null) return 0
  const kids = (n as Node).children
  if (Array.isArray(kids)) return kids.reduce((sum: number, k) => sum + countEngine(k), 0)
  return countEngine(kids)
}

/** The tree with its engine node replaced by `mine`; the rest kept as is. */
function swapEngine<T>(n: T, mine: unknown): T {
  if (isEngine(n)) return mine as T
  if (typeof n !== 'object' || n === null) return n
  const kids = (n as Node).children
  if (kids === undefined) return n
  const swapped = Array.isArray(kids) ? kids.map(k => swapEngine(k, mine)) : swapEngine(kids, mine)
  return { ...n, children: swapped }
}
