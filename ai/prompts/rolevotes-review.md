Review my roleplay bookend votes with me. Work in ~/dotfiles.

Files:
- Votes: ~/.local/state/roleplay/votes.tsv, one per line, tab-separated:
  time, vote id, place (opener or closer), vote (up or down), kind
  (character or universe), name, rolled, line. Times are local.
- Last review: ~/.local/state/roleplay/votes-reviewed-at holds one local time
  (YYYY-MM-DD HH:MM:SS). Only votes after it are waiting. No file means every
  vote is waiting.
- Lines the roleplay-bookends mod wrote: ~/.local/state/roleplay/mod-lines.jsonl.
  Match a vote by `voteId` and `kind` (the vote's place). Older lines that the
  main model wrote are not there: search the transcripts in
  ~/.claude/projects/*/*.jsonl for "r?v=<vote id>" and take the 🎭 line around it.
- Cast, traits and weights: roleplay/roster.tsv (`@character` and `@universe`
  lines set weights). Example lines: roleplay/examples.md.
  `roleplay/bin/roleplay-roll --check` prints the resulting odds.

Steps:
1. Show the waiting votes grouped by character, and by universe for universe
   votes. Under each, show the voted lines with their + or − votes.
2. Say what pattern you see, then suggest changes: a weight, a trait, an
   example line, or nothing. Give each suggestion an ID and let me pick.
3. Make only the changes I accept. Run `roleplay/bin/roleplay-roll --check` and
   `cmds test roleplay` after a roster change.
4. When I say the review is done, write to
   ~/.local/state/roleplay/votes-reviewed-at the time of the newest vote you
   showed me, exactly as it appears in votes.tsv (YYYY-MM-DD HH:MM:SS). Not
   the current time: votes cast during the review then stay waiting for the
   next one. That clears the reminder in Claude Code within 10 minutes.
   This session shows the reminder row too; ignore it.
