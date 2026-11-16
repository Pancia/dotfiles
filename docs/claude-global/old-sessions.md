# Finding an old Claude Code session

- Do not grep the transcripts first. Each one stores the CLAUDE.md it loaded, so any word in a CLAUDE.md matches most of them. Search my prompts instead: `jq -r 'select(.display|test("WORD";"i")) | [.timestamp, .project, .sessionId] | @tsv' ~/.claude/history.jsonl`. Entries before 2025-12-13 have no session id.
- Find the transcript by id in every project folder: `ls ~/.claude/projects/*/<id>.jsonl`. The folder name follows the path the session started from, so one project can have several (`~/TheAkashicRecords` and `~/Vaults/...`).
- If the `.jsonl` is gone, `<id>/subagents/` may still be there, locally and in `~/Cloud/claude-transcripts/`. That backup started on 2026-11-12, so it has nothing older that was already gone.
