# `revive` — what each terminal pane was doing before it died

When the machine loses power, iTerm restores the windows, the tabs, the titles,
the scrollback and each pane's working directory — but the shell in every pane is
brand new, and nothing says what that pane was *for*. With twenty-odd panes alive
for weeks, working that out from scrollback is miserable.

`revive` answers it. Every interactive fish keeps a small journal of what its
pane is doing; a pane that comes back from the dead adopts whatever its
predecessor left and says so.

```
⟲ Before it died, this pane was in ~/vaults/the-akashic-records  (last active Aug 27 00:07)
    running  my-claude-code-wrapper --process-label akr-assistant …
    ⎈ "Explore creative project directions"
  recent:
    jj diff
    ./scripts/score-day.py --today
    revive to resume that session · revive ls for every pane · revive dismiss here
```

Type `revive` in that pane and it `cd`s back and resumes that Claude session —
with the system prompt, model and process label it was launched with.

## Commands

| Command | What it does |
|---|---|
| `revive` | Pick up **this** pane's ghost; the listing below if it has none |
| `revive ls` | Panes that left a record behind, grouped by the live window/tab/pane tree, this one marked |
| `revive <n>` | Pick one up: `cd` there, then resume its Claude session, or offer its command |
| `revive here` | This pane's ghost in full, with its last ten commands |
| `revive go <n>` | Focus the iTerm pane that ghost belongs to |
| `revive live` | What every currently-journaling pane is doing right now |
| `revive dismiss <n>` / `here` / `--all` | Stop reporting a ghost |
| `revive prune [--days N]` | Drop ghosts older than N days (default 30) |

Picking a ghost up dismisses it first, then:

- **It had a Claude session** → resumed straight away, no question. Resuming
  re-runs nothing, and it is the whole point. Goes through `_ccs_resume_entry`,
  the same path `ccs resume` uses for a crashed entry: restore the transcript
  from backup if Claude Code pruned it, archive the entry, `cd` to the cwd the
  session actually ran in, then `my-claude-code-wrapper <launch flags> --resume`.
- **Otherwise** → the command is shown with `Run it again? [Y/n]`. Enter means
  yes; it is still asked because the command could be anything.

The banner carries no ghost number because bare `revive` means "this pane",
and numbering is only settled at listing time anyway.

### Launch flags

Claude Code does not persist `--system-prompt` and friends, so `--resume <id>`
alone brings the akr-assistant back without its persona — the session is there,
the character is not. The wrapper therefore records the flags that shape a
session into the ccs entry as `argv`, and every resume passes them again.

It is an **allowlist** (`_ccs_launch_flags`), not "everything but `--resume`":
argv also carries the initial prompt, and replaying that would send it as a new
message. Telling a flag's value from the prompt needs each flag's arity, so only
named flags survive and an unknown one is dropped. Entries written before this
have no `argv`; resuming one says so and goes ahead without. (The six `@@`
entries from the 2026-09-26 crash were backfilled by hand — `cmds start` in
akashic always passes the same two flags, so they were knowable.)

A clean exit deletes the entry, so for a session saved with `ccsave`
`_ccs_open_finalize` first copies `argv` onto its record in `sessions.json`,
and the picker's `saved` branch passes it back. A session resumed with its
flags records them again, so the saved copy stays current.

Two jq 1.6 traps met on the way: a `--args` positional that starts with `--`
is parsed as jq's own option (and every launch flag does), and NUL-split raw
input is truncated at the first multi-line element. The array is built from
one `--arg` per element, reassembled via `$ARGS.named`.

`bin/revive` serves the read-only verbs for non-fish callers; in fish the
function of the same name wins, because picking a ghost up has to `cd` and re-run
in the caller's own shell.

## Why the iTerm session GUID

`$ITERM_SESSION_ID` is `w<window>t<tab>p<pane>:GUID`. **The GUID survives a
reboot; the prefix does not.** Verified against the 2026-08-27 power loss: nine
GUIDs recorded in `ccs` entries weeks *before* it were still live on restored
panes afterwards, while their `wNtMpK` prefixes had all been reassigned. Splits
survive too — window 2 / tab 1 came back as a two-pane split with both panes'
GUIDs intact.

So the GUID is the pane's identity, and the prefix is never used for anything.
It is also stale even in a live shell: no iTerm shell integration is installed
here, so `$ITERM_SESSION_ID` is set once at spawn and never refreshed — move a
tab between windows and the prefix lies. Grouping therefore comes from asking
iTerm for its current tree, not from the record.

Note **pane**, not tab. A split tab keeps one journal per pane.

## The store

`$XDG_STATE_HOME/term-sessions/`:

```
live/<guid>.rec              the shell currently in that pane
ghosts/<guid>-<epoch>.rec    an orphan a later shell found and adopted
pending/<guid>               that ghost's banner, pre-rendered
dismissed/<guid>             a synthesised ghost waved off (it has no file to delete)
```

**One record per pane, not per shell.** A starting shell that finds an orphan at
`live/<guid>.rec` renames it into `ghosts/` before writing its own. That single
rename is what keeps a replacement shell from clobbering the record it exists to
read, and it buys three things a `<guid>-<pid>-<start>.rec` naming scheme would
not:

- **`exec` works.** `exec` preserves both the pid and the process start time, so
  a pid-based filename is byte-identical across it — and this repo `exec fish`es
  constantly (`.fish`, `bin/disk-cleanup`, `install`, three Hermes entries). The
  exec'd shell ghosts its predecessor instead, which is correct; it just does not
  *announce* it, because a matching pid **and** start time means a shell reload
  rather than a crash.
- **A ghost only exists once something has adopted it**, so "since the last
  restart" is true by construction rather than by filtering on a boot id.
- **The reader needs no liveness check at all.**

### Lifecycle

| Moment | Action |
|---|---|
| shell start | adopt any orphan (one `ps` confirms its owner is really dead), render its banner, then write a fresh header |
| `fish_preexec` | append the command |
| `fish_postexec` | append its exit status and duration |
| `cd` | append the directory (called from `chpwd_hook`) |
| `fish_exit` | delete the record |

`fish_exit` is what makes this usable. It fires on `exit` and when the terminal
goes away, and **not** on SIGKILL or a power cut — exactly the line a ghost has
to fall on. Close a pane on purpose and it erases its own record; only an unclean
death leaves one. Without that, every tab ever closed would come back as a crash
victim, which is the failure mode `ccs` has today (105 dead entries in `open/`,
median age 38 days).

A shell that finds the orphan's owner still *alive* is a nested shell, and does
not journal at all — two writers would interleave into one record.

### Record format

Line-oriented, `key<TAB>percent-encoded-value`, **appended** and never rewritten
(bar compaction every 500 commands). Scalars are last-wins on replay; `cmd` and
`done` lines interleave into the history, and a `cmd` with no `done` after it is
what the pane was doing when it died.

Appending rather than rewriting is both the safe and the cheap choice. Fish
cannot `fsync`, and APFS can land a rename with the data still unflushed, so
`tmp` + `mv` does not actually protect against a power cut — it can leave a
zero-length file. An append can only ever damage the final line, which the reader
drops. It is also 20× cheaper: `printf` + `mv` measured 3.8ms per command against
0.19ms for the bare append. `printf`, `string`, `math` and the redirect are all
builtins, so the hot path forks nothing; the only fork is the one `ps` at shell
start.

Values are encoded with `string escape --style=url`, which
`urllib.parse.unquote` decodes directly — no shim on either side. Commands here
genuinely contain newlines and tabs.

## Two other things it reads

**Claude sessions.** `ccs` entries record `terminal.iterm_session`, so a ghost
can borrow a real session — its title, and the entry `revive` resumes. The
relation is one-to-many — one GUID in the live data has two entries eleven days
apart — so the join takes the newest entry started **while the dead shell was
alive**: after its `lstart`, before the epoch at which the next shell adopted
the ghost.

Both bounds were learned the hard way. With no lower bound, a pane that crashed
Claude weeks ago and later died idle resumes the weeks-old session. And the
upper bound used to be the record's last write, which misses every `@@` launch:
`cmds` starts Claude a few seconds *after* the shell journals the command. That
was four of the thirteen ghosts on 2026-09-26. A pid join is no better for the
same reason — `cmds` spawns a fresh fish, so the entry's pid is not the shell's.
An entry still in `open/` is one whose Claude never exited cleanly, so an
earlier clean exit in the same shell can never be matched.

It also **synthesises** ghosts for panes with no journal record at all, which is
what makes the tool useful on the day it is installed: the panes still open from
a crash that predates it. That is bounded to GUIDs currently live in the iTerm
tree whose entry predates the current boot — seven of them here, against 110
entries in `open/` — so it needs no flag to keep it quiet. Being bounded that way
it is also self-limiting: once a pane has a journal record of its own, nothing is
synthesised for it again.

A synthesised ghost has no file to delete, so dismissing one leaves a tombstone
in `dismissed/` instead. Without that it would come back every time.

**Tab titles.** `name of s` in the iTerm tree carries the running command and
directory (via `fish_title.fish`), so a pane with no record still shows something
real — `… - Nvim (nvim)`, `alt start ~/p/sanctuary (tmux)`.

## Gotchas worth knowing

- **Inside `tell application "iTerm2"`, `tab` is iTerm's own tab class.** Using
  it as a field separator does not fail — it silently writes the word `tab` into
  every field, and the join then matches nothing. The separator is bound outside
  the tell block, and a test pins that.
- **A zombie answers `ps`.** A killed-but-unreaped shell still has a row in the
  process table, so it reads as a live owner and its pane is never adopted. Only
  bites test harnesses (the pty fixture reaps deliberately); in the real world
  iTerm reaps its own children.
- The journal knows nothing about commands run before it was installed.
- Picking up never runs a shell command without showing it and asking first.
  Resuming a Claude session is the one thing it does without asking.

## Tests

`cmds test fish -k revive` and `cmds test python -k revive`.

The fish tests drive a **real pty** (`tests/fish/conftest.py`), because
`fish -c` fires neither `fish_preexec` nor `fish_postexec`, and neither does
`fish -i` reading from a pipe. A test that only calls `emit fish_preexec`
exercises the handler bodies and not the wiring — and a handler that silently
stops firing is the failure this most needs to catch. `pty.fork()` gives the
child the pty as its *controlling* terminal, which `subprocess` with
`start_new_session` does not; without it fish refuses with *"No TTY for
interactive shell (tcgetpgrp failed)"*.

## Why not extend `ccs`

`_ccs_open_register` already records the GUID, tty, cwd, pid and tmux triple, and
`_ccs_open_scan` already implements liveness and crash classification — so
generalising it to every shell is the obvious question. Two reasons not to:
`chpwd` runs that scan over `open/` on every `cd`, and it already had to be
rewritten from jq to one embedded Python pass (330 forks, 7 seconds) to stay
usable — adding twenty-odd always-present shell entries makes the wrong thing
bigger. And the entry semantics there are Claude's: `session_id`,
`transcript_path`, resume-by-id, none of which a shell record uses. `revive`
joins to `ccs` rather than living inside it.
