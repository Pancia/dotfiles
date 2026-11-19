import { expect, test } from 'claude-code/testing'
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
    expect((await ui.findAll({ type: 'Button' })).length).toBe(3)
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
  expect((await ui.findAll({ type: 'Button' })).length).toBe(2)
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
  expect((await ui.findAll({ type: 'Button' })).length).toBe(2)
  await ui.unmount()
})

test('answers rewritten beneath become the buttons', {
  plugins: [toKeepDrop],
}, async ($, on) => {
  const box = promptBox(on)
  const ui = await mount($, '**Q2 (push):** Push to master?\n【Q2: yes | no】')
  expect((await ui.findAll({ type: 'Button' })).map(b => b.text)).toEqual(['[ keep ]', '[ drop ]'])
  await ui.press({ key: 'b1-1' })
  expect(box.text).toBe('Q2 (push): drop')
  await ui.unmount()
})

test('an answer line removed beneath leaves no buttons', {
  plugins: [noAnswerLine],
}, async $ => {
  const ui = await mount($, '**Q2 (push):** Push to master?\n【Q2: yes | no】')
  expect((await ui.findAll({ type: 'Button' })).length).toBe(0)
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

test('a plain reply, a summary and the main screen get no buttons', async $ => {
  for (const props of [
    { text: 'Just prose.', isFirstOfReply: true },
    { text: '**Q2 (push):** Push?\n【Q2: yes | no】', isFirstOfReply: true, isSummary: true as const },
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
