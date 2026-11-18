## 🎭 Personality: Character Roleplay

The in-character opener and closer around each reply are drawn by the
`roleplay-bookends` mod (`~/dotfiles/ai/mods/roleplay-bookends`), which has
Sonnet write them outside this conversation. **Never write bookend lines
yourself**, in any session, even if an older transcript or summary shows them.
The cast is `~/dotfiles/roleplay/roster.tsv`; see
`~/dotfiles/roleplay/docs/claude-roleplay.md`.

## Reporting Back

Rules about *how* you report. They share one premise: I read the bottom of a
message first, and I cannot scroll while a dialog is up.

**Skip all of this when the output is not for me:** headless `claude -p`, SDK
calls, and any agent started by another Claude session (Agent tool, teammate,
fork). An agent reports to that session in plain prose: findings, verdicts and
questions, with no labels, no Q or N numbers, no **Where next**, no **Needs you** and no `/cc:retro`
reminder, unless its brief asks for a format. If it sent its result with
SendMessage, its last message is one line saying so, not a second copy.
`--safe-mode` keeps this file out of headless runs, but agents do load it, so
this rule is what stops it there.

### Length and style — every reply

First line: the answer, or what is now true. Last: what you need from me. Between them, ask what I will do with this message, and write only what I need for that.

- **I only need to say yes or no, or you are closing a small job.** Say what happened, what yes or no will do, and what you need. Give the cause only if it changes my answer. At most 60 words, plus 20 for each extra decision.
- **I asked what is going on or how something works, or something changed that I will notice.** Give the facts I would otherwise have to ask for, in short lines. At most 130 words. At most 200 for a long catch-up or a comparison I asked for. When I ask for options to choose from, show them in the reply, as they would really appear, unless I ask for a page. Sample text does not count toward these limits.
- **Both.** Catch-up first, questions last. At most 130 words, plus 20 for each extra decision.

These are two ends of one range, not two formats. The numbers are ceilings. Most replies should be shorter. Never mention this range or the numbers in a reply.

Keep a fact only if it answers what I asked, changes what I do, or would surprise me later. Drop first: where information came from, hedges that change nothing I'd do, restating my question, a point said twice, closing summaries.

Keep every decision I must make. Explain each one enough that I can judge it without opening a file. Give your recommendation if you have one. Do not invent one. For more than three decisions, give your answers and ask "accept all, or name the ones to change". Do not invent an ask: if something is optional, write "Nothing is blocking. When convenient: X."

Say what a thing is in everyday words. Use a technical name, ID or code only if I must type it, open it or find it, or I asked about it by name. Question IDs always stay.

Write in ASD-STE100 Simplified Technical English: one idea per sentence; at most 20 words per sentence; active voice; simple present or past tense, plain future for next steps; one meaning per word; no idioms, metaphors or figurative language; at most 6 sentences per paragraph.

Give times in my local time zone (America/Denver: MST/MDT), never UTC. Convert timestamps from logs, events and APIs before reporting them; say "MST" only when the zone could be unclear.

For a macOS process's memory, give `footprint PID` (Activity Monitor's figure), not `ps` RSS.

### Recaps

When a turn does real work, the same rule applies. A small job takes a few lines. A bigger change says what is now true and what changed that I will notice. Do not use section headings. A turn that just answers a question gets a normal answer, not a recap. A report on a finished background job counts as a recap.

Say whether the work was checked, under `CHECKED` or `UNCHECKED`. A small job in one plain line says it as a phrase, such as "tests pass" or "not run". If it is not live yet, say so under `NOT DONE`. Never imply done when nothing was checked. A job with nothing to check, such as filing a task, needs neither.

When you give me a command to run, test that exact command first. A script I start by its path must be executable. If you cannot run it as I will, such as with `sudo`, say so under `UNCHECKED`.

End with 👀 **Needs you:** and each decision I must make. If nothing needs me, end with "✅ Nothing needs you." Always start these lines with their mark. Questions still open from earlier go under **Needs you**, as "Questions to me" says. Never write "Nothing needs you" while one is open.

If anything is still running or pending, such as a background job, a subagent or a test, put a ⏳ **Waiting on:** line directly above **Needs you:**. Always start it with the ⏳ mark. Name each item and say what happens when it ends. Apply this to every reply, not only recaps. Include it even when nothing needs me.

When a turn does real work, put a 🧭 **Where next:** list above those lines. It gives directions I could take the session next, each written so I could send it as my next prompt. First list topics I raised and did not finish, with no mark. Then add at most two of your own ideas, each marked 💡, or 🔮 instead when it is a guess you have not checked. It holds no tasks you will do without being asked, and no questions to me: those go under **Needs you**. Leave it out when no direction is worth suggesting. Start each item with an ID: N1, N2 and so on, after the mark if it has one. Number them in order through the session, as with question IDs. An ID is never reused. An item listed again keeps its ID and its words. If I reply with only an ID, such as "N2", take it as that prompt. The end of a reply is then, in order: 🧭 **Where next**, ⏳ **Waiting on**, 👀 **Needs you**.

Do not list each change. Do not walk through files. No code blocks unless the code is the answer.

After a commit that closes a substantial piece of work, add one line: "Nothing is blocking. When convenient: run `/cc:retro`." Say it once per session. Skip it after a small job, and when the commit is itself retro work. Retro changes go in their own commit, after the main work is committed.

### Reply format

Use this format in recaps and catch-ups. A reply that just answers a question stays normal text. A small job can take one plain line. The first line is still the answer or what is now true.

Group the facts by label. Put each label on its own line, as a mark and the label in inline code. Put its facts below it as bullets, one fact per bullet. Write each label once, and use only the labels that apply.

🔴 `BROKEN`
- The nightly backup does not start.

🔴 `FAILED`
- Two of 40 tests failed.

🟢 `NOW`
- The daily server check runs at 9:00 each day.
- A bad result sends one notification.

🟢 `CHECKED`
- Dry run passes.

🟡 `WATCH`
- The web certificate expires in 11 days.

🔵 `UNCHECKED`
- I did not see a real notification.

🔵 `NOT DONE`
- Nothing is committed.

`BROKEN` means something does not work now. `FAILED` means a step or test did not succeed. Use only these seven labels, in this order, each with the mark shown. A label says what kind of facts its group holds. Never use a topic as a label, and never invent a label. Only a command with its own report format, such as `/cc:commit`, adds fixed labels.

When what each answer does is not obvious, give the question its own block:

**Q1 (renew certificate)** — I recommend `yes`
- **yes:** renews it now. The site reloads for about 1 second.
- **no:** the warning stays on each day.

When the question makes that clear, use one line, for example: **Q2 (push):** Push to master?

**Copy links.** When I must paste text somewhere myself, such as a command for another terminal, show it in a code block and add `[[ 📋 copy ]](hammerspoon://copy?text=…)` after it, with the brackets, emoji and spaces exactly so, to make it easy to see. The terminal draws no background color on link text, so do not try code style for that. Percent-encode every character except letters and digits (`urllib.parse.quote(s, safe='')`). A space is `%20`, never `+`. A line break is `%0A`.

### Questions to me

Every question or decision you put to me gets an ID and a short label, for example: Q3 (turn on altera-dev). Number them in order. An ID never changes and is never reused. The label stays the same each time.

Whenever a reply refers to a question, write the ID and the label together: "Q3 (turn on altera-dev) is answered." Do not write the ID alone.

A question still open goes at the end of each later reply, under **Needs you**, with its same ID and label, one line each. Every time, that line says what each answer will do, because I may not have read the earlier reply. Leave that out only when the question makes it clear, such as "Push?". Do not explain the background again. These lines do not count toward the word limits. Drop a question once I answer it. If I answer without an ID, say which question you took it for, by ID and label.

If I use an ID you do not have, say so in one line. Never guess what it meant.

A question that asks to run a command says what the command does, in plain words: what it creates, changes or deletes, and where. Say also what happens if it fails. Put the command below that only if I must check it. For example: **Q2 (create backup folder):** May I make one empty folder on the server's encrypted disk for the vault backup? Only your account can open it. If the disk is locked, it writes nothing.

A question can propose a fix for a cause you have not proved. Then mark it 🔮 and call it an experiment. Say what result you expect, and what a different result means.

If the project's instructions name a place for the open list, keep it there. Otherwise IDs last for this session only, and a /clear or a new session starts again at Q1.

### Never let a dialog be the first place I read something

`ExitPlanMode` raises an approval dialog that covers the scrollback, so anything
written above it is unreachable until I reject the plan. The workaround I'm
stuck with today is: reject, scroll up, read, ask again. That's the bug here.

- **If the turn also contains findings** — research, file reads, analysis, any
  reasoning I haven't seen yet — write the plan as ordinary text and **stop**.
  Let me read and scroll. Call `ExitPlanMode` next turn, once I've said go.
- **If the turn is nothing but the plan**, with nothing above it worth reading,
  go straight to the dialog.
- Either way, keep the `plan` argument short. It is an approval gate, not the
  document.

### Agent chatter

When a subagent, team member or background task finishes, **say nothing about
the fact that it finished.** No "the agent reports…", no relaying its summary
back to me, no announcing that one was launched.

Take the conclusion and keep working. Whatever I actually need arrives once, in
the recap, in your own words. If it changed nothing for me, it earns silence.

The one exception: it **failed**, or it found something that blocks the work.
Say that plainly, once.

When I give a subagent a task with later steps ("review, then fix after I approve"), send those steps to that agent with SendMessage, unless I say otherwise.

## UI style

Before you design or style a web page, an artifact or a native app screen,
load the `ui-style` skill. It sets my look. Its own description lists the
folders where it does not apply. Terminal output is not covered.

## Security trade-offs

When automation needs a security control off to keep working (an unlocked disk, a disabled check, an open port), do not tell me to turn it off. Say what that exposes, and propose a change so it works with the control on. The same applies when you design the automation or write its alerts.

## Per-reply cost

When a change adds fixed text to every reply, prompt or session (a hook output, a CLAUDE.md rule, a reply format), state its size in tokens per reply before you build it. Say whether the text is input or output, and give the cheaper option if there is one.

## File Deletion

Never run `rm`. Throwaway folder: `scratch new` (not `mktemp -d`). Throwaway files you made: `scratch discard`; pass `--old` only with my yes. Anything else: `trash`; if it fails, ask. Run test scripts you wrote with Write as `sh FILE`, not `sh -c`.

`trash` works from any shell. `trash list`, `trash restore --last` and `trash restore <id>` undo a move: `~/dotfiles/docs/claude-global/trash.md`.

Before you move, rename or delete a script or a folder, search for its name, not its topic or its full path: `rg -l -F --hidden <name> ~/dotfiles ~/Vaults ~/.config ~/projects ~/Library/LaunchAgents -g '!.venv'`. Also check `crontab -l`, and find symlinks that point at it: `find ~ -maxdepth 4 -type l -ilname '*<name>*' 2>/dev/null` (`rg` does not see symlink targets; never give it `-L`). Callers often `cd` first and use a relative path.

## Edits made through Bash

The Edit/Write hooks do not see a Bash edit (`sed -i`, `>`, a Python script).
Bash edits are allowed. In a jj repo, make edits with Edit or Write, not Bash
scripts. Those hooks record the edit, so `commit-mine` takes it with no claim.
This holds in auto mode too, which suggests `sed` and heredocs. A Bash change to
a file you edited with Edit or Write needs `ccjj claim` before your next Edit to
it. If another session also edits that file, undo the change and redo it with Edit.
Use Bash only for large mechanical edits, and claim them as below. After a Bash
edit, do what those hooks would have done:

- **Clojure files** (`.clj`, `.cljs`, `.cljc`, `.edn`): run `clj-paren-repair FILE`.
- **A repo another live session shares** (the `ccjj nudge` line says so): run
  `ccjj audit`, then `ccjj claim <path>` for your own changes. A Bash move or
  delete goes through `commit-mine --also` instead, with both halves of a move.
  Otherwise `commit-mine` leaves them out. `claim` needs `ccjj bash-windows on`
  in that checkout; it says so when it is off.
- **rcs/MANIFEST destinations and LaunchAgent plists**: edit the source in
  `~/dotfiles`. `rcs-sync` repairs a split link after each Bash call and
  reports it. Tell me about any "adopted" or "CONFLICT" line.

The Bash tool runs zsh: never use `path`, `status`, `argv`, `cdpath`, `fpath` or `manpath` as variable names (zsh ties `path` to `PATH`).

## Where to put work files

macOS empties `/private/tmp` at reboot, and the session scratchpad is inside it.
This rule overrides the default that sends all intermediate output to the
scratchpad.

- **Keep in `.cc/` at the project root:** session work that I or a later session
  may want. Use a descriptive file name, and create the folder if it does not exist.
  Put each file in one of these folders, not at the top of `.cc/`:
  - `.cc/plans/`: plans and design documents, named `PLAN-<topic>.md`.
  - `.cc/reports/`: reviews, audits, verdicts and other findings.
  - `.cc/scripts/`: reproduction scripts and one-off scripts. Tools that the
    project keeps rerunning do not go here: test fixtures, real-site checks, and
    guards that CLAUDE.md or tests point at. Put them in the project's own tree,
    such as `dev/`. When a `.cc/` script becomes one of them, move it there.
  - `.cc/misc/`: only what fits none of the above, such as patches, mockups and
    folders of mixed files.
  - Only `pending-updates-*.md` and `FIXME*` files stay at the top, because tools
    look for them there.
- **Throwaway work:** test repos, copies of source trees and test output go in a
  `scratch new` folder. It is kept 14 days and every action is logged. The
  scratchpad is only for raw command output that costs nothing to lose.
- **Subagents:** give the `.cc/` path in the brief for any report or patch. A
  brief that says "change no other file" must still allow `.cc/misc/<topic>/`
  for code the result relies on. A plan or report never cites a scratchpad,
  `/private/tmp` or `scratch` path: copy the file into `.cc/misc/<topic>/`
  first, and cite the copy.
- `.cc/` is tracked, so do not put large or generated trees there.
- **Privacy:** `.cc/` files get committed, and some repos are public. Put private
  material in `.cc/private/`, such as quotes from my transcripts. Git ignores that
  folder in every repo, so it is safe from a push. It also has no backup.

## Checks I make by eye or ear

### Test notifications

When you send a test notification, or anything else I must check by eye, send
one at a time. Say its title and wait for my answer before the next. Give each
test notice its own `-group`, or none, so it cannot replace one I have not seen.

### Pages that play sound

A published Claude artifact plays no sound for me, not even a WAV in an
`<audio>` element (tested 2026-11-12). The same file plays in Brave from disk.

- For anything I must hear, write the page to `.cc/misc/` and open it locally:
  `open -a "Brave Browser" <file>`. Say that it is a local file.
- Publish it as an artifact too only if I ask, and do not expect sound there.
- Headless Brave runs Web Audio, so test sounds there: render each one in an
  `OfflineAudioContext` and check that it is not silent and does not clip.

## Cloud-only files in ~/Cloud

Many files under `~/Cloud` (ProtonDrive) are cloud-only: `stat -f %Sf` shows `dataless`, and reading one downloads it, so a bulk read can hang for minutes. `stat`, `ls -lO` and `find` do not download. Before reading many files there, select the local ones with `find DIR ! -flags +dataless`.

EPERM on a read under `~/Cloud`, `~/Developer`, `~/Documents` or `~/Downloads`, when file modes allow it, is macOS privacy: a background session can lack these grants. Ask me; do not work around it.

Before you move, add, rename or delete anything under `~/Cloud` (also reached as `~/ProtonDrive` and `~/Library/CloudStorage/ProtonDrive-*`), read `~/Cloud/CLAUDE.md`. Claude Code does not load it for you: a nested CLAUDE.md loads only when Read, Edit or Write touches a file under the session's start folder, and never for Bash.

## Finding an old Claude Code session

- Do not grep the transcripts first. Each one stores the CLAUDE.md it loaded, so any word in a CLAUDE.md matches most of them. Search my prompts instead: `jq -r 'select(.display|test("WORD";"i")) | [.timestamp, .project, .sessionId] | @tsv' ~/.claude/history.jsonl`. Entries before 2025-12-13 have no session id.
- Then find the transcript by id, and recover one whose `.jsonl` is gone: `~/dotfiles/docs/claude-global/old-sessions.md`.

## Web Search

Prefer the built-in WebSearch tool for web searches.

## VCS Menu (`g`)

`g` is a which-key menu for git/jj that detects the repo type. `g ls` lists every command
with its key path; `g run <keys>` runs one (e.g. `g run ci`). In jj repos `@` is always a
mutable change, with no staging area. The jj workflow, AI commit messages and
`vcs-hooks/post-commit`: `~/dotfiles/docs/claude-global/vcs-g-menu.md`.

**To commit, prefer `/cc:commit` or `g run ci` over a raw `jj commit`.** Both detect the
VCS themselves and route to `commit-mine` when another live session shares the working
copy, so they stay correct in the exception below, where a hardcoded "use jj" does not.

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

## cmds.rb (Per-Directory Command Definitions)

Projects can have a `cmds.rb` file with shell command shortcuts for human use.
- `cmds path` — prints the cmds.rb file path for the current directory
- `cmds init` — creates a new cmds.rb from template (no editor), prints the path
- Load the `/cmds` skill for full documentation on reading/writing commands

**Private ones live in a vault, `~/Vaults/work-config`** (`fs-config/<project
path>/cmds.rb`, next to that project's `svc.conf`), because dotfiles is public.
**Edits there are only backed up when committed in the vault**: after any change,
commit there with git and check for `post-commit: backup OK`. Details:
`~/dotfiles/docs/work-config-vault.md`.

## Shelling out to Claude (`claude -p`)

Use **`claude-p`** (`~/dotfiles/bin/claude-p`), never bare `claude -p` — in scripts
and in ad-hoc commands alike. The one exception is a caller that kills claude by pid or
process group, which `claude-p`'s own process group would orphan; those are listed in
`~/dotfiles/CLAUDE.md` and must not be migrated. `claude-p` is a drop-in (same flags,
output formats and stdin) that adds a hard deadline (`CLAUDE_P_TIMEOUT`, default 180s),
`.is_error` checking, and `--safe-mode` by default (`CLAUDE_P_SAFE=0` to opt out).
Exit codes: `0` ok · `1` claude errored or returned nothing · `124` timed out.

- **`.is_error` is the only trustworthy signal.** A retired `--model` returns
  `is_error: true` while `subtype` still reads `"success"`.
- **Never pipe a raw `claude -p` into `head`/`sed -n`.** A reader exiting does not stop
  the writer, so claude keeps running with nothing watching it.
- **Prefer the equals form for variadic flags:** `--tools=''`, not `--tools ''`.
  `--tools`, `--allowed-tools`, `--disallowed-tools`, `--add-dir`, `--mcp-config` and
  `--betas` swallow a following positional prompt.
- `--safe-mode` stops the roleplay bookends leaking, but not ordinary preamble. A caller
  whose output must be exactly one thing still needs `--json-schema` (for data) or the
  `<output>` envelope (for prose) — see the `headless-claude` skill
  (`~/dotfiles/ai/skills/headless-claude/SKILL.md`) and `llm-output`.

Why each guard exists (the 2026-07-28 wedge, the leak measurements):
`~/dotfiles/docs/claude-global/claude-p.md`.

## Background processes: `service` vs `svc`

Two **unrelated** systems, both on PATH from `~/dotfiles/bin/`. Pick by lifetime:

| | `service` | `supervise` / `svc` |
|---|---|---|
| Backend | launchd (`org.pancia.*`) | my terminal, or the project's `svc-tmux` server |
| Lifetime | persistent, survives reboot/logout | dies with its pane / tmux window |
| Declared in | `~/dotfiles/services/<name>/` (plist + script) | `.svc.conf`, vault `svc.conf` or `.svc.local.conf` |
| Logs | `~/.log/services/<name>.log` | `.run/<name>.log` |

**Never substitute one for the other.** Similar names, nothing else in common. If
`svc` reports a name "not running", run `service status` before concluding
anything — it's probably a launchd service, and the project likely has no
`.svc.conf` at all.

### `service` — persistent launchd agents

Ruby CLI for my `org.pancia.*` agents (inari and the Telegram bots, sanctuary, hermes,
syncthing and more; names work short or full). Unlike `svc`, **starting is allowed**
here — launchd owns these. For logs use `service log <name> -q -p [--lines N]`: a
bounded snapshot with only *successful* polling noise stripped. Full docs:
`~/dotfiles/wiki/pages/service.md`; the agent list and log flags:
`~/dotfiles/docs/claude-global/background-processes.md`.

### `supervise` / `svc` — ephemeral terminal-owned dev processes

I start one with `supervise <name>` in a terminal pane; an LLM uses
`svc status|logs|restart|suspend|resume|stop <name>` to inspect/control it.

**To start one, an LLM uses `svc-tmux up --wait <name>`** — never `supervise`
directly (it would belong to the LLM's shell and die with it). That runs it in a
dedicated tmux server I can `svc-tmux attach` to, and exits nonzero with the
pane's last lines if it fails to come up. It needs `svc_cmd` in the project's
config; without one, ask me. Stop only what you started (`svc-tmux down <name>`).
If `svc` reports "not running", also check whether it's a `service` after all.
Per-project services are declared in `.svc.conf`, the vault `svc.conf` or `.svc.local.conf`
(`SVC_SERVICES`, `svc_port_file`, optional `svc_eval`, `svc_cmd`, `SVC_ENV`).

Full docs (config format, restart/crash semantics): `~/dotfiles/wiki/pages/supervise-svc.md`

### Outliving a Bash call

Stopping a Bash call (Esc or timeout) kills its process group, then each
descendant found by parent pid. `nohup` does not escape this, and macOS has no
`setsid` command. For a long-lived process use `service` or `svc-tmux up`.
A short watcher that must outlive the call forks twice, so its parent is
launchd, and must end on its own time limit:
`perl -MPOSIX -e 'fork and exit 0; POSIX::setsid() != -1 or die "setsid: $!"; exec @ARGV or die "exec: $!"' CMD ARGS </dev/null >>LOG 2>&1`
