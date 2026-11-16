import type { Register } from 'claude-code'

// One switch for two views. Focus view hides tool calls; verbose output shows
// every tool result in full. /focus off now means "show me everything" and
// /focus on means "hide it all again".
//
// The built-in /focus runs first (next). Its result carries no text, so the new
// state is read back from where /focus saves it: "briefTranscript" in
// ~/.claude.json, written before /focus returns. Verbose is the /config
// "Verbose output" row. At startup Claude Code ignores that row while focus
// view is on, so a session opens in focus view unless you left focus off.
const GLOBAL_CONFIG = '/Users/anthony/.claude.json'

export const register: Register = on => {
  on('command.run', { command: 'focus' }, async ($, e, next) => {
    const result = await next(e)
    // /focus off deletes the key rather than writing false.
    let focus: boolean | undefined
    try {
      focus = JSON.parse(await $.fs.read(GLOBAL_CONFIG)).briefTranscript === true
    } catch {
      // unreadable: leave verbose alone
    }
    if (focus === undefined) {
      $.ui.toast('focus-verbose: could not read the focus state; verbose not changed')
      return result
    }
    const { deny } = await $.config.set({ key: 'verbose', value: !focus })
    $.ui.toast(deny ? `focus-verbose: verbose not changed (${deny})` : `Verbose output ${focus ? 'off' : 'on'}`)
    return result
  })
}
