import { expect, mock, test } from 'claude-code/testing'
import type { Engine } from 'claude-code/testing'
import type { On } from 'claude-code'

const REPLY = [
  'Done.',
  '',
  '**Q1 (renew certificate)** — I recommend `yes`',
  '- **yes:** renews it now.',
  '- **no:** the warning stays.',
  '【Q1: yes* | no】',
  '',
  '🧭 **Where next:**',
  '- 💡 N1 Try the band too',
].join('\n')

const mount = ($: Engine, text: string) =>
  $.ui.mount({
    plugin: 'reply-links',
    surface: 'terminal',
    component: 'AssistantMessage',
    props: { text, isFirstOfReply: true },
  })

function promptBox(on: On) {
  const box = { text: '' }
  on('prompt.read', () => ({ value: { text: box.text, cursor: box.text.length } }))
  on('prompt.fill', (_, e) => {
    box.text = e.mode === 'append' ? box.text + e.text : e.text
    return { isFilled: true, text: box.text, cursor: box.text.length }
  })
  return box
}

test('an answer button fills an empty box, a link after it appends', async ($, on) => {
  const box = promptBox(on)
  const ui = await mount($, REPLY)
  // Segments: md0 (Done + Q1 + bullets), row1, md2 (Where next), item3 (N1).
  await ui.press({ key: 'b1-0' })
  expect(box.text).toBe('Q1 (renew certificate): yes')
  await ui.press({ key: 'n3' })
  expect(box.text).toBe('Q1 (renew certificate): yes\nN1')
  await ui.unmount()
})

test('a Where-next ID draws as a filled button, its text beside it', async ($, on) => {
  const box = promptBox(on)
  const ui = await mount($, '🧭 **Where next:**\n- N1 Finish **it**\n- 💡 N2 Try more\n\n👀 **Needs you:** none')
  expect((await ui.find({ key: 'n1' }))?.type).toBe('Button')
  expect((await ui.find({ key: 'md1' }))?.type).toBe('Markdown')
  expect((await ui.find({ key: 'lead2' }))?.text).toBe('- 💡 ')
  await ui.press({ key: 'n2' })
  expect(box.text).toBe('N2')
  await ui.press({ key: 'n1' })
  expect(box.text).toBe('N2\nN1')
  await ui.unmount()
})

test('a one-line question draws yes and no buttons', async ($, on) => {
  const box = promptBox(on)
  const ui = await mount($, '**Q2 (push):** Push to master?\n【Q2: yes | no】')
  await ui.press({ key: 'b1-1' })
  expect(box.text).toBe('Q2 (push): no')
  await ui.unmount()
})

test('a hammerspoon link runs open with the real URL', async ($, on) => {
  const ran: string[][] = []
  on('process.run', (_, e) => {
    ran.push([...e.argv])
    return { value: { exitCode: 0, stdout: '', stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
  })

  const ui = await mount($, 'See [[ 📋 copy ]](hammerspoon://copy?text=hi)')
  await ui.press({ key: 'md0', link: { href: 'https://reply-links.invalid/0' } })
  expect(ran).toEqual([['open', 'hammerspoon://copy?text=hi']])
  await ui.unmount()
})

const closer = (tier: 'prepend' | 'append') => ({
  name: 'rp',
  tier,
  register(on: On) {
    on('ui.render', { component: 'AssistantMessage' }, async ($, e, next) => {
      const inner = await next(e)
      const { Box, Text, Button } = $.ui.resolve(e)
      return (
        <Box flexDirection="column">
          {inner}
          <Box flexDirection="row">
            <Text>CLOSER</Text>
            <Button key="vote" label="+" onPress={() => undefined} />
          </Box>
        </Box>
      )
    })
  },
})

for (const tier of ['prepend', 'append'] as const) {
  test(`with a wrapping mod ${tier === 'prepend' ? 'above' : 'beneath'}, both parts draw and press`, { plugins: [closer(tier)] }, async ($, on) => {
    const box = promptBox(on)
    const ui = await mount($, '**Q2 (push):** Push to master?\n【Q2: yes | no】')
    // yes, no, submit, and the closer's vote.
    expect((await ui.findAll({ type: 'Button' })).length).toBe(4)
    await ui.press({ key: 'b1-0' })
    expect(box.text).toBe('Q2 (push): yes')
    await ui.press({ plugin: 'rp', key: 'vote' })
    await ui.unmount()
  })
}

test('with a pass-through mod beneath, the buttons still draw', {
  plugins: [{ name: 'passer', tier: 'append', register(on: On) { on('ui.render', { component: 'AssistantMessage' }, async ($, e, next) => next(e)) } }],
}, async $ => {
  const ui = await mount($, '**Q2 (push):** Push to master?\n【Q2: yes | no】')
  expect((await ui.findAll({ type: 'Button' })).length).toBe(3)
  await ui.unmount()
})

// Mods beneath that rewrite the reply's text on its way to the engine. A test
// plugin's register runs on its own, so each spells its strings inline: it
// cannot use a variable from this file.
const toMain = {
  name: 'rewriter',
  tier: 'append' as const,
  register(on: On) {
    on('ui.render', { component: 'AssistantMessage' }, async ($, e, next) =>
      next({ ...e, props: { ...e.props, text: e.props.text.replace('master', 'main') } }),
    )
  },
}
const toKeepDrop = {
  name: 'rewriter',
  tier: 'append' as const,
  register(on: On) {
    on('ui.render', { component: 'AssistantMessage' }, async ($, e, next) =>
      next({ ...e, props: { ...e.props, text: e.props.text.replace('【Q2: yes | no】', '【Q2: keep | drop】') } }),
    )
  },
}
const noAnswerLine = {
  name: 'rewriter',
  tier: 'append' as const,
  register(on: On) {
    on('ui.render', { component: 'AssistantMessage' }, async ($, e, next) =>
      next({ ...e, props: { ...e.props, text: e.props.text.replace('\n【Q2: yes | no】', '') } }),
    )
  },
}

test('a rewrite beneath is drawn, not the text this mod received', {
  plugins: [toMain],
}, async $ => {
  const ui = await mount($, '**Q2 (push):** Push to master?\n【Q2: yes | no】')
  expect(await ui.find({ type: 'Markdown', text: /Push to main\?/ })).toBeDefined()
  expect(await ui.find({ type: 'Markdown', text: /master/ })).toBeUndefined()
  expect((await ui.findAll({ type: 'Button' })).length).toBe(3)
  await ui.unmount()
})

test('answers rewritten beneath become the buttons', {
  plugins: [toKeepDrop],
}, async ($, on) => {
  const box = promptBox(on)
  const ui = await mount($, '**Q2 (push):** Push to master?\n【Q2: yes | no】')
  expect((await ui.findAll({ type: 'Button' })).map(b => b.text)).toEqual(['[ keep ]', '[ drop ]', '[ submit ↵ ]'])
  await ui.press({ key: 'b1-1' })
  expect(box.text).toBe('Q2 (push): drop')
  await ui.unmount()
})

test('an answer line removed beneath leaves no answer buttons', {
  plugins: [noAnswerLine],
}, async $ => {
  const ui = await mount($, '**Q2 (push):** Push to master?\n【Q2: yes | no】')
  // The label link is still drawn, so the reply keeps only its submit button.
  expect((await ui.findAll({ type: 'Button' })).map(b => b.text)).toEqual(['[ submit ↵ ]'])
  await ui.unmount()
})

test('a label link then its answer button completes the label', async ($, on) => {
  const box = promptBox(on)
  const ui = await mount($, '**Q2 (push):** Push to master?\n【Q2: yes | no】')
  await ui.press({ key: 'md0', link: { href: 'https://reply-links.invalid/0' } })
  expect(box.text).toBe('Q2 (push): ')
  await ui.press({ key: 'b1-0' })
  expect(box.text).toBe('Q2 (push): yes')
  await ui.unmount()
})

test('a plain reply gets the submit button alone, drawn as written', async $ => {
  const ui = await mount($, 'Just prose.')
  expect((await ui.findAll({ type: 'Button' })).map(b => b.text)).toEqual(['[ submit ↵ ]'])
  expect(await ui.find({ type: 'Markdown', text: 'Just prose.' })).toBeDefined()
  await ui.unmount()
})

test('a summary and an empty block get no buttons', async $ => {
  for (const props of [
    { text: '**Q2 (push):** Push?\n【Q2: yes | no】', isFirstOfReply: true, isSummary: true as const },
    { text: '  \n', isFirstOfReply: true },
  ]) {
    const ui = await $.ui.mount({ plugin: 'reply-links', surface: 'terminal', component: 'AssistantMessage', props })
    expect((await ui.findAll({ type: 'Button' })).length).toBe(0)
    await ui.unmount()
  }
})

const compose = ($: Engine, surfaces: string[], traits: string[] = []) =>
  $.prompt.compose({ model: 'claude-opus-5-5', promptModel: 'claude-opus-5-5', surfaces, tools: [], outputStyle: null, traits } as never)

test('the rule joins the system prompt in a terminal session only', async ($, on) => {
  on('prompt.compose', () => ({ sections: [{ id: 'intro', text: 'hi', scope: 'shared' as const }] }))
  const ids = async (surfaces: string[], traits: string[] = []) =>
    (await compose($, surfaces, traits)).sections.map(s => s.id)
  expect(await ids(['terminal'])).toEqual(['intro', 'reply-links:answer-buttons'])
  expect(await ids([])).toEqual(['intro'])
  expect(await ids(['terminal'], ['print'])).toEqual(['intro'])
})

function sender(on: On) {
  const sent: { text: string; asUser?: true }[] = []
  on('prompt.submit', (_, e) => {
    sent.push({ text: e.text, asUser: e.origin.kind === 'plugin' ? e.origin.asUser : undefined })
    return { text: e.text }
  })
  return sent
}

test('the submit button sends the box as the user, then empties it', async ($, on) => {
  const box = promptBox(on)
  const sent = sender(on)
  const ui = await mount($, REPLY)
  await ui.press({ key: 'n3' })
  await ui.press({ key: 'submit' })
  expect(sent).toEqual([{ text: 'N1', asUser: true }])
  expect(box.text).toBe('')
  await ui.unmount()
})

test('the submit button sends nothing from an empty box or a slash command', async ($, on) => {
  const box = promptBox(on)
  const sent = sender(on)
  const ui = await mount($, REPLY)
  await ui.press({ key: 'submit' })
  box.text = '/compact'
  await ui.press({ key: 'submit' })
  expect(sent).toEqual([])
  expect(box.text).toBe('/compact')
  await ui.unmount()
})

test('a reply with links alone still gets the submit button', async $ => {
  const ui = await mount($, '**Q2 (push)** — push to master?')
  expect(await ui.find({ key: 'submit' })).toBeDefined()
  await ui.unmount()
})

test('a slash command button fills an empty box, and never a draft', async ($, on) => {
  const box = promptBox(on)
  const toasts: string[] = []
  on('ui.toast', (_, e) => {
    toasts.push(String((e as { text?: unknown }).text ?? e))
    return { value: undefined }
  })
  on('command.list', () => ({
    value: [{ name: 'cc:retro', description: 'Retro', source: 'plugin' }],
  }))
  const ui = await mount($, 'When convenient: run `/cc:retro`.')
  // The paragraph as written (md0), then the row (cmds1) with one button.
  expect(await ui.find({ type: 'Markdown', text: 'When convenient: run `/cc:retro`.' })).toBeDefined()
  expect((await ui.find({ key: 'c1-0' }))?.text).toBe('[ /cc:retro ]')
  await ui.press({ key: 'c1-0' })
  expect(box.text).toBe('/cc:retro')
  box.text = 'my draft'
  await ui.press({ key: 'c1-0' })
  expect(box.text).toBe('my draft')
  expect(toasts).toEqual(['Empty the prompt box first: /cc:retro runs only from its start.'])
  // A reply with a command row alone ends in the submit button too.
  expect(await ui.find({ key: 'submit' })).toBeDefined()
  await ui.unmount()
})

const listing = (on: On, names: string[]) => {
  let calls = 0
  on('command.list', () => {
    calls++
    return { value: names.map(name => ({ name, description: name, source: 'builtin' })) }
  })
  return () => calls
}

test('a command click into a box read as empty appends, never replaces', async ($, on) => {
  const modes: string[] = []
  on('prompt.read', () => ({ value: { text: '', cursor: 0 } }))
  on('prompt.fill', (_, e) => {
    modes.push(e.mode ?? 'replace')
    return { isFilled: true, text: e.text, cursor: e.text.length }
  })
  listing(on, ['clear'])
  const ui = await mount($, 'Run /clear.')
  await ui.press({ key: 'c1-0' })
  expect(modes).toEqual(['append'])
  await ui.unmount()
})

test('a draft that starts with "/" is kept', async ($, on) => {
  const box = promptBox(on)
  on('ui.toast', () => ({ value: undefined }))
  listing(on, ['clear'])
  const ui = await mount($, 'Run /clear.')
  box.text = '/Users/anthony/x.log shows an error, why?'
  await ui.press({ key: 'c1-0' })
  expect(box.text).toBe('/Users/anthony/x.log shows an error, why?')
  await ui.unmount()
})

test('an answer click replaces a command a click left', async ($, on) => {
  const box = promptBox(on)
  listing(on, ['clear'])
  const ui = await mount($, '**Q1 (go):** Run /clear?\n【Q1: yes | no】')
  // md0 (question), row1 (answers), cmds2 (its command), then submit.
  await ui.press({ key: 'c2-0' })
  expect(box.text).toBe('/clear')
  await ui.press({ key: 'b1-0' })
  expect(box.text).toBe('Q1 (go): yes')
  await ui.unmount()
})

test('an answer click in a later block replaces a command a click left', async ($, on) => {
  const box = promptBox(on)
  listing(on, ['clear'])
  const first = await mount($, 'Run /clear.')
  await first.press({ key: 'c1-0' })
  expect(box.text).toBe('/clear')
  await first.unmount()
  // This block names no command, so it asks for no names of its own.
  const second = await mount($, '**Q1 (go):** Ok?\n【Q1: yes | no】')
  await second.press({ key: 'b1-0' })
  expect(box.text).toBe('Q1 (go): yes')
  await second.unmount()
})

test('a block a mod beneath empties gets no submit button', {
  plugins: [{
    name: 'emptier',
    tier: 'append',
    register(on: On) {
      on('ui.render', { component: 'AssistantMessage' }, async ($, e, next) => next({ ...e, props: { ...e.props, text: '' } }))
    },
  }],
}, async $ => {
  const ui = await mount($, 'Some text.')
  expect((await ui.findAll({ type: 'Button' })).length).toBe(0)
  await ui.unmount()
})

test('a list that answers late redraws, and a lost ask is asked again', async ($, on) => {
  const clock = mock.clock(on)
  let calls = 0
  const redraws: unknown[] = []
  on('ui.invalidate', (_, e) => {
    redraws.push(e)
    return { value: undefined }
  })
  on('command.list', async () => {
    calls++
    if (calls === 1) return new Promise<never>(() => undefined)
    await clock.sleep(2_000)
    return { value: [{ name: 'clear', description: '', source: 'builtin' }] }
  })
  // The first ask never answers: the block draws after 1 s with no row.
  let mounting = mount($, 'Run /clear.')
  await clock.advance(1_000)
  await (await mounting).unmount()
  // Past 10 s it is taken as lost; the next ask answers 2 s late.
  await clock.advance(10_000)
  mounting = mount($, 'Run /clear.')
  await clock.advance(1_000)
  const ui = await mounting
  expect(await ui.find({ key: 'c1-0' })).toBeUndefined()
  await clock.advance(1_500)
  expect(calls).toBe(2)
  expect(redraws.length).toBe(1)
  await ui.unmount()
})

test('a failed command list draws no row and is not asked on every draw', async ($, on) => {
  let calls = 0
  on('command.list', () => {
    calls++
    throw new Error('down')
  })
  for (let i = 0; i < 3; i++) {
    const ui = await mount($, 'Run /clear.')
    expect(await ui.find({ key: 'c1-0' })).toBeUndefined()
    await ui.unmount()
  }
  expect(calls).toBe(1)
})

test('a command list that never answers lets the reply draw, with no row', async ($, on) => {
  on('command.list', () => new Promise<never>(() => undefined))
  const clock = mock.clock(on)
  const mounting = mount($, 'Run /clear.')
  await clock.advance(1_000)
  // The mount ends: the reply is drawn with no command row, submit alone.
  const ui = await mounting
  expect((await ui.findAll({ type: 'Button' })).map(b => b.text)).toEqual(['[ submit ↵ ]'])
  await ui.unmount()
})
