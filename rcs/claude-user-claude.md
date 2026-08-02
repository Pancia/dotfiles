## 🎭 Personality: Character Roleplay

Bookend each response with an **opener** and a **closer** in character. Everything between them is written normally — keep universe jargon out of the technical content.

**Selection.** A `UserPromptSubmit` hook injects the character, self-contained:

> `[🎭 Character Roll: «Togusa» 🔍 GHOST IN THE SHELL — Methodical · earnest · old-school detective instincts]`

Use exactly that character. The roster lives in `~/dotfiles/ai/roleplay/roster.tsv`, deliberately not here — the hook reads it, so each prompt carries one line rather than all 57. (`roleplay-roll --list` / `--check`.)

**No roll tag → no bookends.** Its absence means a non-interactive session — headless `claude -p`, SDK, nested helper — where they'd be chatter in a payload slot rather than flavour.

**Signature lines.** Where a character has one famous quote, the tag says whether it is UNLOCKED or spent this roll (1/3 odds, `ROLEPLAY_CATCHPHRASE`). Obey it; when spent, reach for a less-worn part of the character.

### 📖 Format

**Opener** — blockquote at the top:
> 🎭 **«Character Name»** <emoji> `UNIVERSE` — *"In-character line relevant to the task ahead."*

**Closer** — same header, at the bottom. Mix freely between a straight closing line, a salute or status report, a brief scene beat in italics, or a quip about how the task went.

Keep both **brief** and **contextually relevant**.

## File Deletion

Prefer `trash` over `rm` when deleting files. If `trash` fails, try `rm` as a fallback — but always as a separate command, never chained together (no `trash ... || rm ...`).

`trash` is a subcommand CLI, usable from any shell (the `bin/trash` shim forwards to the Fish function):
- `trash <paths>` (or `trash put <paths>`) — move files to the trash
- `trash list [--json]` — list trashed files, newest first; `--json` emits one object per entry with a stable `id`, original `path`, and `present` flag
- `trash restore --last` — restore the most recently trashed file
- `trash restore <id>` — restore a specific entry by the `id` shown in `trash list` (`restore` is a top-level alias for `trash restore`)

To trash a file literally named `put`/`list`/`restore`/`help`, use `trash put <name>`.

## Web Search

Prefer the built-in WebSearch tool for web searches. Kagi search (`mcp__kagi__kagi_search_fetch`) is also available as an alternative.

## VCS Menu (`g`)

`g` is a which-key modal menu for git/jj that auto-detects the repo type. Use `g ls` to see all available commands.

**Non-interactive CLI** (for scripting and AI agents):
- `g ls` / `g help` — list all commands with key paths and shell commands
- `g run <keys>` — execute by key path (e.g. `g run cc`, `g run ci`, `g run s`)

**Jujutsu (jj) workflow:** In jj repos (`.jj/` directory), the working copy (`@`) is always a mutable change — no staging area. Key operations:
- `jj describe` — set/update the commit message on `@` (stays in same change)
- `jj commit` — describe `@` and create a new empty change on top (`describe` + `new`)
- `jj new` — create new empty change on top of `@`
- Advance + push — `jj commit` → `jj bookmark set master -r @-` → `jj git push`

AI-generated commit messages available via `g run ci` (`ai_jj_commit` / `ai_git_commit`).

**To commit, prefer `/cc:commit` or `g run ci` over a raw `jj commit`.** Both
detect the VCS themselves (via `vcs-status-for-ai`, which takes the *nearest*
marker walking up) and route to `commit-mine` when another live session shares
the working copy. Because they compute the answer instead of assuming it, they
stay correct in the exception below, where a hardcoded "use jj" does not.

**Exception — in a git worktree of a jj repo, use `git`.** Claude Code's
`--worktree` creates a *git* worktree with no `.jj` of its own, so `jj` there
walks up and resolves to the **parent** repo. Two ways that bites:

- `jj commit` commits the **parent's** working copy — very likely another
  session's in-flight work — while your own changes stay uncommitted.
- `jj st` / `jj log` report the **parent's** state, so your own edits look like
  they vanished. Do not "fix" that by redoing the work.

Tell by location: you are in one if the cwd is under `.claude/worktrees/<name>/`,
or if `.git` is a **file** rather than a directory. Use `git` for everything
there — it is a complete workflow, not a fallback: the commits come back to the
parent as a jj bookmark of the same name automatically, and the parent's working
copy is left untouched. `bin/cc-worktree-nudge` re-asserts this every prompt when
it detects the situation, and overrides any project CLAUDE.md that says
otherwise.

**VCS Hooks:** Repos can define `./vcs-hooks/post-commit` (executable) to run after commit-like operations through `g`.

## cmds.rb (Per-Directory Command Definitions)

Projects can have a `cmds.rb` file with shell command shortcuts for human use.
- `cmds path` — prints the cmds.rb file path for the current directory
- `cmds init` — creates a new cmds.rb from template (no editor), prints the path
- Load the `/cmds` skill for full documentation on reading/writing commands

## Shelling out to Claude (`claude -p`)

Use **`claude-p`** (`~/dotfiles/bin/claude-p`), never bare `claude -p` — in scripts
and in ad-hoc commands alike. It is a drop-in: same flags, same `--output-format`
(text / json / stream-json), same stdin handling. It adds the three guards bare
`claude -p` lacks:

- **A hard deadline.** `timeout -k` in its own process group, so a wedged child
  cannot outlive the call. `CLAUDE_P_TIMEOUT` (default 180s) to adjust.
- **Real error detection.** It asks for JSON underneath and checks `.is_error`.
  A retired or unavailable `--model` returns `is_error: true` while `subtype`
  still reads `"success"` — so **`.is_error` is the only trustworthy signal**.
  An unvalidated caller otherwise treats the error text as a real answer.
- **A clean room.** `--safe-mode` by default (`CLAUDE_P_SAFE=0` to opt out), which
  disables CLAUDE.md discovery, hooks, skills, plugins and MCP config while leaving
  auth, model selection, built-in tools and permissions normal.

Exit codes: `0` ok · `1` claude errored or returned nothing · `124` timed out.

**Never pipe a raw `claude -p` into `head`/`sed -n`.** A reader exiting does not stop
the writer, so the claude process keeps running with nothing watching it. (`claude-p`
buffers to a file, so that SIGPIPE lands on its own `cat`.)

**Prefer the equals form for variadic flags:** `--tools=''`, not `--tools ''`.
`--tools`, `--allowed-tools`, `--disallowed-tools`, `--add-dir`, `--mcp-config` and
`--betas` all swallow a following positional prompt and then die with "Input must be
provided either through stdin or as a prompt argument".

On 2026-07-28 a headless claude wedged at ~98% CPU past 2.7GB RSS with no output and
had to be killed by hand. The trigger is still unknown — the retired-model theory was
tested and disproved (that exits rc=1 in ~2s) — so a deadline is the defence.

**The roleplay bookends used to leak into headless output** — roughly two runs in
three, and `--append-system-prompt` never reliably suppressed them. `--safe-mode`
does (measured 3/3 clean on a prompt that leaked 2/2), so `claude-p` passes it by
default and the fallback rule at the top of this file tells a rollless session to omit
the bookends anyway. What safe-mode does *not* suppress is ordinary preamble, so a
caller whose output must be exactly one thing still needs `--json-schema` (for data)
or the `<output>` envelope (for prose) — see `~/dotfiles/CLAUDE.md`,
"Constraining headless output", and `llm-output`.

## Background processes: `service` vs `svc`

Two **unrelated** systems, both on PATH from `~/dotfiles/bin/`. Pick by lifetime:

| | `service` | `supervise` / `svc` |
|---|---|---|
| Backend | launchd (`org.pancia.*`) | my terminal |
| Lifetime | persistent, survives reboot/logout | dies with the shell that started it |
| Declared in | `~/dotfiles/services/<name>/` (plist + script) | `.svc.conf` / `.svc.local.conf` in the project |
| Logs | `~/.log/services/<name>.log` | `.run/<name>.log` |

**Never substitute one for the other.** Similar names, nothing else in common. If
`svc` reports a name "not running", run `service status` before concluding
anything — it's probably a launchd service, and the project likely has no
`.svc.conf` at all.

### `service` — persistent launchd agents

Ruby CLI managing my `org.pancia.*` agents: **inari** (and all six Telegram
bots), sanctuary, hermes, lakshmi, copyparty, syncthing, vpc, tv-board, ziplog,
bookmark-manager, youtube-transcribe, wget_server, music-backup, disk-snapshot.
Names work short or full — `inari` == `org.pancia.inari`.

```
service status                          # table: SERVICE / PID / STATUS / LAST START / AGO
service start|stop <name>
service restart <name> [--log]
service log <name> -q -p [--lines N]    # agent-friendly: bounded snapshot, noise stripped
service log <name> --grep 'Error|Traceback|Exception' -p
```

`service log` auto-detects a non-TTY and prints a bounded snapshot instead of
hanging in `less +GF`; `-q` strips known polling noise — **only successful**
Telegram `getUpdates` responses, so failed polls (502 / 429 / 409, and the
"terminated by other getUpdates request" duplicate-instance alarm) still show.
Unlike `svc`, **starting is allowed** here — launchd owns these, not my terminal.

Full docs: `~/dotfiles/wiki/pages/service.md`

### `supervise` / `svc` — ephemeral terminal-owned dev processes

`supervise` and `svc` run long-lived dev
processes that stay **owned by my terminal** while an LLM can **restart** them on
demand. I start one with `supervise <name> -- <cmd>` (usually a `cmds` entry); an
LLM uses `svc status|logs|restart|stop <name>` to inspect/restart it — but
**never starts one itself** (if `svc restart` says "not running", ask me — or check
whether it's a `service` after all). Per-project
services are declared in `.svc.conf` / `.svc.local.conf` (`SVC_SERVICES`,
`svc_port_file`, optional `svc_eval`).

Full docs (read if you need the config format, restart/crash semantics, or to add
it to a project): `~/dotfiles/wiki/pages/supervise-svc.md`
