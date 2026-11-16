# Claude Code doctor — 2026-11-15

Read-only pass. Nothing has been changed. Token figures are estimates (chars / 4).

**Scan windows.** 50 newest transcripts = 1 day (all 2026-11-15, mostly Altera
workers). 600 newest = 5 days (Nov 10–15). MCP and slash-command use was also
counted over every transcript changed in the last 90 days (2,676 files).

## Summary

The install is healthy and current. The main cost is the two always-loaded
instruction files: this repo's `CLAUDE.md` is 70k chars (est. 17.5k tokens, over
the ~40k-char warning line), and the global one is 27.6k chars (est. 6.9k tokens,
in every project). About two-thirds of the project file can be cut or moved to
files that load on demand. Three claude.ai connectors, one MCP server and one
command are unused. Every change below is reversible.

## Inventory

| Component | Type | Scope | Uses (total since install) | Used in window? | Est. resident tokens | Verdict |
|---|---|---|---|---|---|---|
| pyright-lsp | plugin (LSP) | user | 1,122 | yes | ~0 | keep |
| plainify | mod (`CLAUDE_CODE_PLUGIN_DIRS`) | user | 0 (counter) | 1 `/plainify` in 90 d | ~30 | keep — built 2026-11-05, too new to judge |
| playwright | MCP | local (dotfiles) | n/a (no counter) | 427 calls in 90 d, last Nov 9 | deferred | keep |
| kagi | MCP | local (dotfiles) | n/a (no counter) | 0 calls in 90 d | deferred | **remove** (declutter only, no token saving) |
| claude.ai Gmail | connector | account | n/a | 1,950 calls in 90 d, last Nov 8 | deferred | keep — now shows only `authenticate`, so it needs a re-login |
| claude.ai Google Calendar | connector | account | n/a | 0 calls in 90 d | deferred | **remove** |
| claude.ai Google Drive | connector | account | n/a | 0 calls in 90 d | deferred | **remove** |
| claude.ai Claude Docs | connector | account | n/a | 1 call in 90 d | ~1.2k (3 resident schemas + server instructions) | **remove** |
| fish | skill | user + project | 78 | yes | ~40 | keep |
| cmds | skill | user + project | 12 | last Nov 6 | ~70 | keep |
| ui-style | skill | user | 0 | — | ~110 | keep — added 2026-11-12, too new |
| cc:commit / cc:retro / cc:pending-updates | commands | user | 133 / 30 / 21 | yes | ~60 | keep |
| prompt:build | command | user | 2 | last used early May | ~20 | **remove** |
| easel, telemetry, privacy, diff, agents-md, plugin-authoring | plugins | built-in | — | — | — | not touching (built in) |
| anthropic-skills:* (synced) | skills | account | — | — | — | not touching (account-provided) |
| `~/.claude/CLAUDE.md` (= `rcs/claude-user-claude.md`) | memory | global, every project | — | — | ~6,900 | trim (check 10) |
| `CLAUDE.md` (this repo) | memory | project | — | — | ~17,500 | trim + migrate (checks 3, 4) |

## Proposed actions

### Check 0 — setup health: no findings
One native install (`~/.local/bin/claude` → 2.1.325), on PATH, matching
`installMethod: native`. No npm or `~/.claude/local` leftovers. All settings files
parse. Agent definitions are valid. `critique`, `doc-writer` and `optimizer` exist
in both `.claude/agents/` and `~/.claude/agents/`, but in different folders, so
this is an override, not a collision. All `ai/skills/*/SKILL.md` frontmatter parses.

### Check 1 — unused extensions
1. **kagi**: run `/mcp disable kagi` in this project (undo: `/mcp enable kagi`).
   Applies here only. The global CLAUDE.md "Web Search" line still mentions Kagi;
   drop that sentence in `rcs/claude-user-claude.md`.
2. **Google Calendar, Google Drive, Claude Docs connectors**: run
   `/mcp disable claude.ai Google Calendar` (and the same for the other two), or
   turn them off on claude.ai. Per project with `/mcp`; claude.ai turns them off
   everywhere.
3. **prompt:build**: add `"skillOverrides": {"prompt:build": "off"}` to
   `rcs/claude-settings.json` (the source of the hardlinked
   `~/.claude/settings.json`). Undo: remove the key.

### Check 2 — local vs checked-in duplicates: no removals
The only local file is the global CLAUDE.md, which loads in every project. Its
overlaps with this repo's `CLAUDE.md` (`claude-p`, `service` vs `svc`, the
jj-worktree rule, the work-config vault, `.cc/` layout) are not project-specific,
so the global copy stays and the project copy shrinks (check 3). No contradictions
that change behaviour.

### Check 3 — cut derivable content from `CLAUDE.md` (est. ~13k chars, ~3.3k tokens)
The current text stays recoverable with `jj file show -r @- CLAUDE.md`.

| Section (current line) | Why it goes | Est. chars |
|---|---|---|
| Repository Structure (29) | `ls` shows it | 1,200 |
| XDG Base Directories (509) | `fish/conf.d/00_xdg.fish` shows it | 1,070 |
| Neovim Prefixes (805), Primary Tools (893), Installation (501) | derivable from `nvim/`, `install` | 1,200 |
| Hours Calculation (905), Website Crawler (940) | API/usage readable from the scripts | 900 |
| File Locations (993) | derivable, and its counts are stale ("6 LaunchAgents") | 450 |
| LaunchAgent Services command list (53) | duplicates `service --help` and the global file; keep the two `reload`/`_ENSURE_SERVICES` bullets | 600 |
| Concurrent sessions: "Inside a worktree of a jj repo" paragraph (184) | said twice already (VCS section, global file); cannot arise here | 700 |
| Private per-project config (336), Claude Code Project Artifacts (454) | the global file says the same | 1,300 |
| Headless Claude calls (618): wedge history, variadic-flag paragraph, safe-mode leak story | the global file says the same | 2,000 |
| Shell Commands table (583): long rows that restate their own sections (`ccs`, `commit-mine`, `ccjj`, `cc-worktree`, `revive`, `claude-p`, `llm-output`, `roleplay-roll`, `cmds`) | shorten each to one line + pointer | 3,000 |

### Check 4 — move the rest to on-demand files (est. ~28k chars, ~7k tokens)
New skills go in `ai/skills/<name>/SKILL.md` plus a `cc-config.json` entry, like
the existing ones. Every "never" rule stays in the root file.

| Source | Destination | Stays in root |
|---|---|---|
| Music streaming (349, 8.1k) | skill `music-server` | never add `--delete` to remote-sync; find disks by DUID; `$MUSIC_LIBRARY` never points at the mount; `/mnt` is normally locked, never auto-unlock |
| Headless Claude calls + Constraining headless output (618–804, 11.9k after check 3's cut) | skill `headless-claude` | check `.is_error`; `llm-output` has no raw-text fallback; SDK callers need `cli_path` |
| Crashed Session Titles (256, 5.3k) | `docs/ccs.md` | one pointer line |
| Session-scoped jj commits (216, 2.6k) | already in `docs/cc-jj-sessions.md` | the four rules: use `commit-mine`, `--also` for Bash moves, `ccjj audit`, `claude-p` writes no journal |
| Live Transcribe + whisper-serverd (474–498, 2k) | `docs/live-transcribe.md` | never pass `--save-audio` in tests |
| Hermes Commands (543, 2.1k) | `docs/hermes.md` | the reserved-keys table |
| Testing (813, 3.9k): component table, fish-syntax note | `docs/testing.md` | `cmds test` only, never `pytest`; register every tree in `COMPONENTS` |

**Before / after:** 70,092 chars (over the ~40k warning line) → about 29,000
chars (under it). Saves est. ~10k tokens in every session started in this repo.

### Check 7 — version: up to date
2.1.325, the current `latest`. Background updates are off by your choice
(`autoUpdates: false`, `CLAUDE_CODE_SKIP_AUTO_UPDATE`).

### Check 8 — auto mode default
This session already runs in auto mode, but no settings file sets
`permissions.defaultMode`. It looks like the account default. Proposal: add
`"defaultMode": "auto"` under `permissions` in `rcs/claude-settings.json`, so it
stays on if that default changes. Applies to every project. If auto mode is not
available at startup, Claude Code falls back to default mode with a notice.

### Check 9 — pre-approvals: none proposed
The 1-day pass found ~40 denials. Nearly all were declined by hand at the prompt.
The repeated ones are `git` reads (these ask only in untrusted repos, so a global
rule would be wrong) and `mkdir` (writes). The rest were one-off compound commands.

### Check 10 — what /usage flagged
| Share | Row | Action |
|---|---|---|
| 57% | Start fresh when you switch tasks | advice: `/clear` |
| 51% | Run fewer sessions at once (up to 21) | advice; also linked to the hook timeouts below |
| 24% | Trim `~/.claude/CLAUDE.md` (7k tokens/request) | **proposal below** |
| 17% | Sessions active over many hours | advice |
| 10% | `general-purpose` subagents | advice below |

**Global CLAUDE.md trim** (edit `rcs/claude-user-claude.md`; the destination is a
hardlink). Move detail to `docs/claude-global/*.md` with a one-line pointer each.
`@` imports would save nothing, because they load eagerly.

| Section (line) | Keep in place | Est. chars saved |
|---|---|---|
| Shelling out to Claude (310) | use `claude-p`; equals form for variadic flags; never pipe raw `claude -p` into `head` | 2,000 |
| Background processes (351–417) | the two-row table; LLMs start svc with `svc-tmux up --wait`; the double-fork line | 2,300 |
| VCS Menu `g` (256) | prefer `/cc:commit`; in a git worktree of a jj repo use `git` | 1,500 |
| Finding an old session (246), Pages that play sound (228), cmds.rb (297) | pointer lines | 1,500 |

27.6k → about 20k chars. Saves est. ~1.8k tokens per request, in every project.

**general-purpose subagents.** That agent type is built in. It runs on the parent
model (Opus here) unless a call passes `model` or a default subagent model is set
(`CLAUDE_CODE_SUBAGENT_MODEL` in the settings `env`). 84 were started in 5 days;
`cc:retro`'s "implement in a subagent" step is one source. Recommendation: no
change, because those agents write code. If cost matters more, set the env var to
`sonnet`; it then applies to every subagent without its own `model`.

## Warnings

### Check 5 — slow hooks (each is 1–3 events in 5 days, during heavy load)
- `ccs-title-hook` (Stop): 3 timeouts, 6–10 s. It is a copy job, so it could run async.
- `reply-style-nudge` (UserPromptSubmit): 1 timeout at 7.1 s. This one delays the prompt.
- `jj-snapshot.sh stop` (Stop): 1 timeout at 5 s.
- `alt heartbeat` (Pre/PostToolUse): median 15–470 ms, worst 5 s in one worker.

### Check 6 — always-resident context in this repo (est.)
| Component | Est. tokens |
|---|---|
| `CLAUDE.md` (this repo) | 17,500 |
| global CLAUDE.md | 6,900 |
| skill and command listing | ~2,500 |
| `alt prime` SessionStart hook output | ~1,500 |
| Claude Docs connector | ~1,200 |

The `alt prime` hook is in this repo's untracked `.claude/settings.json`. It tells
every dotfiles session to use `alt recon` instead of the Agent tool, which
conflicts with `cc:retro`. Run `/context` for exact live figures.

## Revised after critique (2026-11-15)

The full critique is `.cc/reports/REVIEW-doctor-cleanup.md`. These revisions replace the
matching parts above.

**Order of work**
1. Wait until the other session commits its edits to `CLAUDE.md` (the cmus lines in the
   Music section) and `rcs/claude-settings.json`. Then do the restructure in its own commit.
2. Register `ui-style` in `ai/cc-config.json` before any other edit there. Any change to
   that file re-syncs, and the sync deletes unregistered skill links.

**Checks 3 and 10 together.** A rule leaves one file only if the other file keeps it:
- The global file keeps the vault rules (the private config lives in the vault, and edits are
  backed up only when committed) and the rule that output which must be exactly one thing
  needs `--json-schema` or the `<output>` envelope. Its pointer then names the new skill.
- The project file keeps "this repo is public" and "use `service`, not `launchctl`".
- The project root keeps the list of callers that stay on bare `claude -p` on purpose.
  Global line 312 gets an exception clause, and `bin/tab-organize` gets a comment.
- Global pointers use absolute paths (`~/dotfiles/docs/claude-global/...`). Each pointer
  states the rule, not only the topic.

**More lines stay in the root files**
- Music: run `crypt-mounted` before writing to `/mnt`; private folders under `/mnt` get mode
  750 or 700; the age key never goes on the server; `/music` stays `noauto`.
- Headless: never re-parse `.result`; prefer floating model aliases.
- Other: `commit-mine` exit 4 means retry; tests use `--output-dir` (the default is
  `~/Cloud/transcripts`); check `pgrep` before testing live transcribe; the Hermes
  silent-duplicate rule; the `cmds test --` trap; the `ccjj forget` warning.
- "Keep Python out of fish strings" moves into the fish skill.
- Global: in a worktree, do not redo work that seems gone, and how to tell you are in one;
  `svc` needs `svc_cmd`, else ask; stop only what you started; check `service status` before
  trusting `svc`; `nohup` does not escape and macOS has no `setsid`.

**Reach.** The ccs section gets a required-read line, in the same pattern as the fish rule:
read `docs/ccs.md` before editing `ccs.fish`, the wrapper, `ccs-title-hook`, `ccsave-hook`
or `cc-transcript-backup`. Skill descriptions name concrete files and commands.

**Extensions**
- kagi: also remove its allow rule in `rcs/claude-settings.json` and the Kagi sentence in the
  global file. Kagi is set up only for dotfiles, so that sentence is wrong elsewhere.
- Calendar, Drive and Claude Docs: turn them off in Claude Code only (`/mcp disable`), not on
  claude.ai. The scan cannot see use in the web or desktop apps.
- prompt:build: remove it from the global group in `ai/cc-config.json`, not with
  `skillOverrides`.

**Auto mode pin: now not recommended.** Headless runs start in default mode today. With the
pin, they would start in auto mode, and the classifier could approve their actions.
Interactive sessions already run in auto mode.

**New estimates.** Project file is about 32–34k characters, down from 70k (saves about 9k
tokens). Global file is about 21.5k, down from 27.6k (saves about 1.5k tokens in every project).
