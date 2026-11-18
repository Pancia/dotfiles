// Control for F1: the test's ui.toast hook does see the mod's own toasts.
import { expect, test } from 'claude-code/testing'

test('T1 a failed open is toasted (control)', async ($, on) => {
  const toasts: string[] = []
  on('ui.toast', (_, e) => {
    toasts.push(JSON.stringify(e))
    return { value: undefined } as never
  })
  on('process.run', () => ({ value: { exitCode: 1, stdout: '', stderr: 'nope', isStdoutTruncated: false, isStderrTruncated: false } }))
  const ui = await $.ui.mount({
    plugin: 'reply-links',
    surface: 'terminal',
    component: 'AssistantMessage',
    props: { text: 'See [[ 📋 copy ]](hammerspoon://copy?text=hi)', isFirstOfReply: true },
  })
  await ui.press({ key: 'md0', link: { href: 'https://reply-links.invalid/0' } })
  expect(toasts.length).toBe(1)
  await ui.unmount()
})
