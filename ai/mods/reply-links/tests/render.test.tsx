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
  // Segments: md0 (Done + Q1 + bullets), row1, md2 (N1).
  await ui.press({ key: 'b1-0' })
  expect(box.text).toBe('Q1 (renew certificate): yes')
  await ui.press({ key: 'md2', link: { href: 'https://reply-links.invalid/1' } })
  expect(box.text).toBe('Q1 (renew certificate): yes\nTry the band too')
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
