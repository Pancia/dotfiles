// reply-links: in a reply, question labels and Where-next IDs become links,
// and an answer line under a question (【Q4: yes* | no】, which RULE below
// teaches the model) becomes a row of buttons. A click puts that text in the
// prompt box. Only the "[ submit ↵ ]" button, at the end of every reply block
// (plain ones too), sends: it sends the box as the person's own message and
// empties it. A slash command
// the session knows ("/cc:retro") gets a button in a row under its paragraph,
// which puts it in the box, so Enter runs it; nothing runs on the click itself.
//
// Only the drawing changes: the stored reply, and what the model reads, stay
// as written. A click is answered by the mod only in the fullscreen terminal;
// a cmd-click on a link there opens its placeholder address.

import type { Register } from 'claude-code'

import { addToBox, commandToBox, isLoneCommand, linkify, mayHaveCommand } from './linkify'
import type { Action } from './linkify'

const SECTION = 'reply-links:answer-buttons'

// Drawn dim at the start of each row of answer buttons.
const PREFIX = '↳ 💬'
// And at the start of each row of slash-command buttons.
const COMMAND_PREFIX = '↳ ⌘'

// The fill of a button that is not the recommended one: a mid gray, seen on a
// dark and a light terminal alike. `text` was white here: the theme is the
// dark one in both macOS modes, and the terminal's own light colors fix only
// the text, so a white fill vanished on the light background (2026-11-18).
// A raw color, a little lighter than the theme's `inactive` (153).
const FILL = 'rgb(185,185,185)'

// The session's command names, asked for again after a minute: a reply is
// drawn many times, and a command added mid-session shows up soon enough. A
// failed ask is kept 10 s, so a broken list is not asked on every draw, and
// one ask is shared by the draws that wait on it. A reply waits at most 1 s
// for it, then draws with no command row.
const COMMANDS_TTL_MS = 60_000
const COMMANDS_FAIL_TTL_MS = 10_000
const COMMANDS_WAIT_MS = 1_000
const NONE: ReadonlySet<string> = new Set()
let commandCache: { at: number; ttl: number; names: ReadonlySet<string> } | null = null
let commandAsk: Promise<ReadonlySet<string>> | null = null

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

    // The names of the slash commands, asked for only when a reply may hold
    // one. A failed or slow ask gives no command row; the rest still draws.
    const commandsFor = async (text: string): Promise<ReadonlySet<string>> => {
      if (!mayHaveCommand(text)) return NONE
      if (commandCache && Date.now() - commandCache.at < commandCache.ttl) return commandCache.names
      commandAsk ??= $.command
        .list()
        .then(list => {
          const names: ReadonlySet<string> = new Set(list.map(c => c.name))
          commandCache = { at: Date.now(), ttl: COMMANDS_TTL_MS, names }
          return names
        })
        .catch(() => {
          commandCache = { at: Date.now(), ttl: COMMANDS_FAIL_TTL_MS, names: NONE }
          return NONE
        })
        .finally(() => {
          commandAsk = null
        })
      // A refused timer must not fail the drawing: then wait for the ask alone.
      let timer: { cancel: () => void } | undefined
      const late = new Promise<ReadonlySet<string>>(resolve => {
        try {
          timer = $.clock.after(COMMANDS_WAIT_MS, () => resolve(NONE))
        } catch {
          // No timer here.
        }
      })
      try {
        return await Promise.race([commandAsk, late])
      } finally {
        timer?.cancel()
      }
    }

    // Every reply block is drawn here, so each ends in the submit button; an
    // empty one goes on untouched.
    if (e.props.text.trim() === '') return next(e)
    const names = await commandsFor(e.props.text)
    const quick = linkify(e.props.text, names)

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
    const known = props.text === e.props.text ? names : await commandsFor(props.text)
    const linked = props.text === e.props.text ? quick : linkify(props.text, known)
    // The commands this reply offers, for telling a click's command in the
    // box from a draft.
    const offered = linked.segments.flatMap(s => (s.kind === 'commands' ? s.commands : []))

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
        let text: string
        if (action.kind === 'command') {
          const put = commandToBox(box.text, action.text, known, offered)
          if (put === null) {
            $.ui.toast(`Empty the prompt box first: ${action.text} runs only from its start.`)
            return
          }
          text = put
        } else {
          // An answer replaces a lone command a click left: under it, the
          // answer would go to the command as its arguments.
          const base = isLoneCommand(box.text, known, offered) ? '' : box.text
          text = addToBox(base, action.text)
        }
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

    // Sends the prompt box as the person's own message, as Enter does, then
    // empties the box if it still holds what was sent: a draft typed while
    // the send waited for a running turn is kept.
    const submit = async () => {
      try {
        const box = await $.prompt.read()
        const text = box.text.trim()
        if (text === '') {
          $.ui.toast('The prompt box is empty.')
          return
        }
        // A plugin's prompt does not run a slash command.
        if (text.startsWith('/')) {
          $.ui.toast('Press Enter to run a slash command.')
          return
        }
        const sent = await $.prompt.submit({ text, asUser: true })
        if (sent.drop !== undefined) {
          $.ui.toast(`Not sent: ${sent.drop}`)
          return
        }
        const after = await $.prompt.read()
        if (after.text === box.text) await $.prompt.fill({ text: '' })
      } catch (err) {
        $.ui.toast(`Could not send the prompt: ${String(err)}`)
      }
    }

    const parts = linked.segments.map((s, i) =>
      s.kind === 'item' ? (
        // "- 💡 [ N1 ] text": the ID filled as an answer button is, the text
        // after it wrapping in its own column. One blank row after the last
        // item of the list, when more text follows.
        <Box
          key={`item${i}`}
          flexDirection="row"
          marginLeft={s.indent}
          marginBottom={i < linked.segments.length - 1 && linked.segments[i + 1]?.kind !== 'item' ? 1 : 0}
        >
          <Box key={`lead${i}`} flexShrink={0}>
            <Text>{s.mark ? `${s.lead}${s.mark} ` : s.lead}</Text>
          </Box>
          <Box key={`cell${i}`} flexShrink={0} marginRight={1}>
            <Button key={`n${i}`} label={s.id} plain onPress={() => run(linked.actions.get(s.href))}>
              <Text backgroundColor={FILL} color="inverseText">
                {`[ ${s.id} ]`}
              </Text>
            </Button>
          </Box>
          {s.rest ? (
            <Box key={`rest${i}`} flexGrow={1} flexShrink={1}>
              <Markdown
                key={`md${i}`}
                text={s.rest}
                onLinkPress={link => run(linked.actions.get(link.href))}
                pressableLinks={s.hrefs}
              />
            </Box>
          ) : null}
        </Box>
      ) : s.kind === 'markdown' ? (
        <Markdown
          key={`md${i}`}
          text={s.text}
          onLinkPress={link => run(linked.actions.get(link.href))}
          pressableLinks={s.hrefs}
        />
      ) : s.kind === 'commands' ? (
        // "↳ ⌘ [ /cc:retro ] [ /plainify ]" under the block that named them.
        <Box
          key={`cmds${i}`}
          flexDirection="row"
          flexWrap="wrap"
          marginLeft={s.indent}
          marginBottom={i < linked.segments.length - 1 ? 1 : 0}
        >
          <Box key={`lead${i}`} marginRight={1}>
            <Text dimColor>{COMMAND_PREFIX}</Text>
          </Box>
          {s.commands.map((c, j) => (
            <Box key={`cell${i}-${j}`} marginRight={2}>
              <Button key={`c${i}-${j}`} label={c} plain onPress={() => run({ kind: 'command', text: c })}>
                <Text backgroundColor={FILL} color="inverseText">
                  {`[ ${c} ]`}
                </Text>
              </Button>
            </Box>
          ))}
        </Box>
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
                  backgroundColor={a.isPrimary ? 'claude' : FILL}
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

    // Every reply this mod draws ends in the submit button, whatever it holds:
    // answer rows, Where-next IDs, command rows or links alone.
    const hasButtons = true
    const mine = (
      <Box flexDirection="row">
        <Box width={2} flexShrink={0}>
          <Text>{props.isFirstOfReply ? '⏺' : ' '}</Text>
        </Box>
        <Box flexDirection="column" flexGrow={1} flexShrink={1}>
          {parts}
          {hasButtons ? (
            // One send button at the end of a reply that has buttons.
            <Box key="submitRow" flexDirection="row" marginTop={1}>
              <Button key="submit" label="submit" plain onPress={() => submit()}>
                {/* Green, so it is not read as the recommended answer. */}
                <Text backgroundColor="success" color="inverseText" bold>
                  {'[ submit ↵ ]'}
                </Text>
              </Button>
            </Box>
          ) : null}
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
