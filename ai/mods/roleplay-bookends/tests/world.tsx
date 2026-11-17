// The engine beneath the mod, shared by the event tests. `claude plugin test`
// runs only *.test.ts(x) files, so this helper is never run on its own.
//
// Any $ call no hook answers fails with "no implementation for …", so every
// engine call the mod makes is answered here, once, for every test file.
// What a file needs to vary (processes, the model, whether a prompt starts a
// turn) it passes in `opts`.
//
// All state is built inside world(): each test file gets its own copy of this
// module, and module state would carry across the tests in one file. Do not
// import ../hooks/register here, for the same reason (ai/mods/README.md).
import { mock } from 'claude-code/testing'
import type { Engine, MockClock } from 'claude-code/testing'
import type { On } from 'claude-code'

// The tag `roleplay-roll --votes` prints (roleplay/bin/roleplay-roll).
export const TAG = '[🎭 Character Roll: «Togusa» 🔍 GHOST IN THE SHELL — Methodical · earnest || vote id: ab12]'
export const ROLL = JSON.stringify({ hookSpecificOutput: { hookEventName: 'UserPromptSubmit', additionalContext: TAG } })
const USAGE = { input_tokens: 1, output_tokens: 1, cache_read_input_tokens: 0, cache_creation_input_tokens: 0 }

export type RunAnswer = { exitCode?: number; stdout?: string; stderr?: string }

export type WorldOpts = {
  // A process.run answer by argv; it may throw, as a timed-out run does.
  // Default: the roll tag for roleplay-roll, empty output for anything else.
  run?: (argv: readonly string[]) => RunAnswer
  // The model's text for a prompt. Default: "OPENER line" or "CLOSER line".
  answer?: (prompt: string) => string
  // The turn a submitted prompt starts before prompt.submit resolves, as an
  // idle prompt does; undefined folds it into a running turn and starts none.
  // Default: every prompt starts one.
  turnFor?: (text: string) => string | undefined
}

export type World = {
  clock: MockClock
  // Every prompt sent to the model, toasts shown, and open pane ids.
  asks: string[]; toasts: string[]; panes: string[]
  // The mod's $.store, and the current session id (a test may change it).
  store: Map<string, unknown>; sid: string
  registered: { name: string; immediate?: true }[]
}

const kindOf = (prompt: string) => (prompt.includes('OPENER') ? 'OPENER' : 'CLOSER')

export function world($: Engine, on: On, opts: WorldOpts = {}): World {
  const w: World = {
    clock: mock.clock(on, { now: 1_000_000 }),
    asks: [], toasts: [], panes: [], store: new Map(), sid: 'sess-1', registered: [],
  }
  const run = opts.run ?? ((argv): RunAnswer => ({ stdout: argv.join(' ').includes('roleplay-roll') ? ROLL : '' }))
  const answer = opts.answer ?? (prompt => `${kindOf(prompt)} line`)
  const turnFor = opts.turnFor ?? (text => `t-${text.length}`)

  on('process.run', (_, e) => {
    const r = run(e.argv)
    return {
      value: {
        exitCode: r.exitCode ?? 0, stdout: r.stdout ?? '', stderr: r.stderr ?? '',
        isStdoutTruncated: false, isStderrTruncated: false,
      },
    }
  })
  on('model.complete', (_, e) => {
    w.asks.push(e.prompt)
    return { value: { isAnswered: true as const, text: answer(e.prompt), usage: USAGE } }
  })
  on('session.id', () => ({ value: w.sid }))
  on('command.register', (_, e) => {
    w.registered.push({ name: e.name, ...(e.immediate ? { immediate: e.immediate } : {}) })
    return { value: { command: e.name } }
  })
  on('store.get', (_, e) => ({ value: structuredClone(w.store.get(e.key)) }))
  on('store.set', (_, e) => {
    w.store.set(e.key, structuredClone(e.value))
    return { value: undefined }
  })
  on('ui.panes', () => ({
    value: w.panes.map(id => ({ id, title: id, isShown: true, isFocused: true, isPlaced: true })),
  }))
  on('ui.toast', (_, e) => {
    w.toasts.push(e.text)
    return { value: undefined }
  })
  on('ui.open', (_, e) => {
    w.panes.push(e.id)
    return { value: { isPlaced: true } }
  })
  on('ui.close', (_, e) => {
    w.panes = w.panes.filter(p => p !== e.id)
    return { value: undefined }
  })
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('session.end', (_, e) => ({ sessionId: e.sessionId }))
  on('prompt.submit', async (_, e) => {
    const turnId = turnFor(e.text)
    if (turnId) await $.turn.start({ text: e.text, turnId })
    return { text: e.text }
  })
  on('turn.start', (_, e) => ({ turnId: e.turnId }))
  on('turn.complete', (_, e) => ({ text: e.answer }))
  return w
}

export async function start($: Engine, w: World) {
  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })
  await w.clock.settle()
}
