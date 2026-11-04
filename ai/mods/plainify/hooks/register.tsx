import { atom, read, update } from 'claude-code'
import type { Register } from 'claude-code'

import type { LastReply, PlainView } from '../types'

// The CLI does the work (ai/templates/plainify.md + claude-p + llm-output),
// so the prompt has one home and the command line can use it too.
const PLAINIFY = '/Users/anthony/dotfiles/bin/plainify'
const PANE = 'plainify'

const last = atom({ plugin: 'plainify', key: 'last' } as const, { question: '', answer: '' } as LastReply, {
  shape: 'last-1',
})
const view = atom(
  { plugin: 'plainify', key: 'view' } as const,
  { status: 'idle', text: '', words: 0, originalWords: 0, source: '' } as PlainView,
  { shape: 'view-2' },
)

const wordCount = (s: string) => s.split(/\s+/).filter(Boolean).length

// The question of the main-loop turn in flight; lost on reload, which only
// means the next rewrite runs without it.
let question = ''

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    await $.command.register({
      name: 'plainify',
      description: 'Rewrite the last reply shorter and plainer (Haiku), shown in a pane',
    })
    return next(e)
  })

  on('turn.start', async ($, e, next) => {
    if (!e.agentId) question = e.text
    return next(e)
  })

  on('turn.complete', async ($, e, next) => {
    const done = await next(e)
    if (!e.agentId && e.reason === 'answer' && e.answer.trim()) {
      const answer = e.answer
      await update($, last, () => ({ question, answer }))
    }
    return done
  })

  on('command.run', { command: 'plainify' }, async $ => {
    const { question: q, answer } = await read($, last)
    if (!answer) return { text: 'plainify: there is no reply to rewrite yet.' }

    // Run again on the same reply while the pane is up: close it. A pane only
    // takes Escape / ctrl+x x while it holds the keyboard, so this is the
    // close that works from the prompt.
    const isUp = (await $.ui.panes()).some(pane => pane.id === PANE)
    if (isUp && (await read($, view)).source === answer) {
      await $.ui.close({ id: PANE })
      return {}
    }

    await update($, view, () => ({ status: 'running', text: '', words: 0, originalWords: wordCount(answer), source: answer }))
    // Transparent: the pane's default dark backdrop made theme-coloured text
    // unreadable on a light terminal theme. Focus, so Escape closes it at once;
    // typing hands the keys back to the prompt.
    void $.ui.open({ id: PANE, title: 'Plain version', backgroundColor: 'transparent', closeOnEscape: true, focus: true })

    // Runs after the command returns, so the prompt stays free while Haiku works.
    void (async () => {
      try {
        const argv = q ? [PLAINIFY, '--question', q] : [PLAINIFY]
        const r = await $.process.run(argv, { stdin: answer, timeoutMs: 120_000 })
        const out = r.stdout.trim()
        await update($, view, (v): PlainView =>
          r.exitCode === 0 && out
            ? { ...v, status: 'done', text: out, words: wordCount(out) }
            : { ...v, status: 'error', text: `plainify exited ${r.exitCode}\n${r.stderr.trim().slice(-600)}` },
        )
      } catch (err) {
        await update($, view, (v): PlainView => ({ ...v, status: "error", text: String(err) }))
      }
    })()

    // Nothing in the transcript: the rewrite lives in the pane only.
    return {}
  })

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    const { Box, Text, Markdown } = $.ui.resolve(e)
    const v = await read($, view)
    return (
      <Box flexDirection="column">
        {v.status === 'idle' && <Text dimColor>Run /plainify to rewrite the last reply.</Text>}
        {v.status === 'running' && <Text dimColor>Rewriting the last reply with Haiku…</Text>}
        {v.status === 'error' && <Text color="red">{v.text}</Text>}
        {v.status === 'done' && <Markdown text={v.text} />}
        {v.status === 'done' && (
          <Text dimColor>
            {v.words} words, was {v.originalWords} · Esc or /plainify again to close
          </Text>
        )}
      </Box>
    )
  })
}
