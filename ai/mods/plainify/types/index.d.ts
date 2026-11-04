export type LastReply = { question: string; answer: string }
export type PlainView = {
  status: 'idle' | 'running' | 'done' | 'error'
  text: string
  words: number
  originalWords: number
  /** The reply this rewrite is of, so a second /plainify on it closes the pane. */
  source: string
}

declare module 'claude-code' {
  interface PluginState {
    plainify: { last: Shaped<LastReply>; view: Shaped<PlainView> }
  }
}
