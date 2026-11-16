export type Line = {
  name: string
  emoji: string
  universe: string
  text: string | null
  ms: number
  voteId?: string
  failed?: string
}

// Votes since the last review: all of them, and those a week old or more.
export type VoteCount = { waiting: number; old: number }

declare module 'claude-code' {
  interface PluginState {
    'roleplay-bookends': {
      openers: Record<string, Line>
      closers: Record<string, Line>
      votes: VoteCount
    }
  }
}
