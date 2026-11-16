export type Line = {
  name: string
  emoji: string
  universe: string
  text: string | null
  ms: number
  voteId?: string
  failed?: string
  // Random mode only: the overall chance of this character and of its
  // universe, as fractions. Rows from before odds were drawn have none.
  odds?: Odds
}

export type Odds = { c: number; u: number }

// A vote's direction, and what it is on.
export type Way = 'up' | 'down'
export type Kind = 'character' | 'universe'

// Votes since the last review: all of them, and those a week old or more.
export type VoteCount = { waiting: number; old: number }

// One row of `roleplay-roll --roster`: the character, its signature line
// ('' for none), its universe's share of rolls and its own overall share.
export type Char = {
  universe: string
  name: string
  emoji: string
  traits: string
  sig: string
  u: number
  c: number
}

// random: a new character on every typed prompt (the vote links show).
// session: one character for the whole session, changed only by Reroll or Pick.
export type Mode = 'random' | 'session'

// The session's mode (null until session.start reads the saved default) and,
// in session mode, its one character (null until rolled).
export type Pin = { mode: Mode | null; who: Char | null }

declare module 'claude-code' {
  interface PluginState {
    'roleplay-bookends': {
      openers: Record<string, Line>
      closers: Record<string, Line>
      votes: VoteCount
      pin: Pin
      filter: string
      myVotes: Record<string, Way>
    }
  }
}
