# Critique: retro suggestions from the media-sync session

Date: 2026-11-12. Read-only review. Behaviour tests ran only in the session
scratchpad and with one throwaway launchd label (`org.example.cc-waittest`,
removed after each probe). No jj command was run. Nothing in ~/dotfiles, ~/AKR or
~/Vaults was changed except this file.

Session facts for items 3 and 4 (which searches ran, how many notices were sent,
what the user said) come from the brief. I did not check them in the transcript.

## 1. commit-mine runs the vault's post-commit hook: CHANGED

The diagnosis is true but too narrow. No route of `/cc:commit` runs
`vcs-hooks/post-commit`, not only the `commit-mine` route. `ai/commands/commit.md`
never mentions vcs-hooks, and its normal route is a raw `jj commit -m` (step at
line 222) or `git commit`. Only `bin/g` runs the hook (`_run_vcs_hook`, line 173,
called at line 471 when every step of a commit chain exits 0).

Answers to the checks:

- **`g run ci` already runs it after routing to commit-mine.** `ci` is
  `chain('ai_jj_commit', JJ_STATUS)`, and `_chain_has_commit` matches
  `ai_jj_commit`. `ai_jj_commit` calls `ccjj commit` when `should-scope` exits 0
  and returns its exit code. So the proposed fix in ccjj would run the hook twice
  under `g run ci`: once in ccjj, then again in g.
- **The vault hook is executable** (`-rwxr-xr-x`). The session used `sh` because
  the AKR `CLAUDE.md` (line 302) and the hook's own header (lines 6-7) say "after a
  bare `jj commit`, run `sh vcs-hooks/post-commit` by hand".
- **~/dotfiles has no vcs-hooks.** `~/Vaults/music/vcs-hooks/post-commit` exists
  too, also executable.
- **Tests.** ccjj tests are `tests/lib/python/test_ccjj.py`, in the registered
  `lib/python` component. `docs/cc-jj-sessions.md` says nothing about vcs-hooks.

What the proposed fix would break:

- **Time budget.** Inari gives the hook 600 s (`HOOK_TIMEOUT`), because the bundle
  write to ProtonDrive can take minutes. An agent's Bash call has a 120 s default
  timeout. A kill during `git bundle create` leaves `akr.bundle.lock`, which the
  hook clears only after 60 minutes. Until then, step 1 fails for every commit,
  Inari's 05:00 job included. Running the hook synchronously inside `commit-mine`
  makes that kill likely.
- **The shared lock.** `ccjj commit` takes `ai_jj_commit`'s lockdir. If the hook ran
  before the lock is released, Inari's job would get exit 4 ("locked", not
  retried) and skip the night.
- **Exit codes.** 1, 2, 4 and 5 have meanings, and `ai_jj_commit` returns early on
  any non-zero code. A hook failure must not change ccjj's exit code.

**Revised fix, part 1 (covers every `/cc:commit` route):** add a step 7 to the "normal
procedure" in `ai/commands/commit.md`, after "Bookmark", and the same sentence in
the session-scoped section: "If `<repo root>/vcs-hooks/post-commit` is
executable, run it from the repo root with `run_in_background` (or a 600000 ms
timeout). Report a non-zero exit under `FAILED`. The commit still stands." It runs
after the bookmark moves, so the bundle (`--all`) includes it. Then change the
AKR `CLAUDE.md` line 302 and the hook header to say that `/cc:commit` and `g` run
it, and only a bare `jj commit` does not. Add one line to
`docs/cc-jj-sessions.md`: `ccjj commit` does not run vcs-hooks; `/cc:commit` and
`g` do.

**Part 2 (covers a direct `commit-mine` call):** part 1 does not cover an agent
that calls `commit-mine` outside `/cc:commit`, and agents are told to do that:
the `ccjj nudge` text (lib/python/ccjj.py, `cmd_nudge`) and the dotfiles
`CLAUDE.md` both say "Commit with `commit-mine -m`". So at the end of a
successful `cmd_commit` (after the "committed and verified" line, so after the
lock and `retire()`), print one line and do not run anything: "note:
vcs-hooks/post-commit is executable and was not run; run it from <root> in the
background". The exit code stays 0. That avoids the double run, the lock and the
timeout problems. Under `g run ci` the line is printed and `g` then runs the hook,
which is harmless noise. Add one test in `tests/lib/python/test_ccjj.py`: the
note appears when the file is executable, and not when it is missing or not
executable.

If a code route that runs the hook is wanted later, put the logic in one small
script that both `g` and `/cc:commit` call, not in ccjj.

Smaller defect in the same code: `_run_vcs_hook` in `g` ignores the hook's exit
code, so a failed backup reads as success unless you read the hook's output.

## 2. CLAUDE.md lines about `_ENSURE_SERVICES`: CHANGED

The claims about the code are true:

- `_ENSURE_SERVICES &` (fish/config.fish line 61) is outside the
  `status is-interactive` guard. The comment at line 54 says that `func &` runs in
  the foreground. So every fish start runs it: `fish -c`, fish scripts such as
  `bin/trash` (`#!/usr/bin/env fish`), and each step of a `g` chain.
- It links and `launchctl load`s any `services/*/*.plist` whose installed copy is
  missing or has another inode. The find matches only `*.plist`, so
  `*.plist.disabled` stays out.
- `launchctl load` on a loaded job is a no-op. Verified: it prints `Load failed:
  5`, exits 0, and launchd keeps the old program arguments. Unload then load
  picks up the edit, and does not run a job that has no RunAtLoad.

It matters more than the retro says, because ~/dotfiles is shared. Right now
`services/cc-transcript-backup/` is uncommitted in the shared working copy
(status `A`), and its plist is already installed (same inode) and loaded. So any
agent's `trash` call can load a plist that another session has not finished.

"Does not say" is partly false. The "Music streaming" section (line 425) already
says that `_ENSURE_SERVICES` reinstalls any `services/*/*.plist` on shell startup.
The "RC Metadata System" paragraph (line 98) says rcs-sync reminds you to
`service restart`. The "LaunchAgent Services" section says neither.

The second proposed line is wrong for scheduled jobs. `service restart` (bin/service
lines 287-291) runs stop, unload, load, then `launchctl start`. So it stops a run
that is going, and runs a calendar job at once. Commit 1857dd9e removed exactly
that behaviour from `_ENSURE_SERVICES`.

**Revised lines for "LaunchAgent Services":**

- A new or changed `services/*/*.plist` is installed and loaded at the next fish
  start of any kind, including `fish -c` and fish scripts such as `trash`
  (`_ENSURE_SERVICES` in fish/config.fish). A RunAtLoad or KeepAlive job starts
  then. Rename the file to `*.plist.disabled` to keep it out.
- `launchctl load` ignores a job that is already loaded. To apply an edit to a
  loaded plist, `service restart <name>`. That stops a run in progress and also
  starts a new run now. For a scheduled job, use `service reload <name>`, which
  stops a run in progress but does not start one.

That needs a small `service reload` (unload, then load, then check
`launchd_loaded?`; restart without the final `launchctl start`). The section
opens with "use the `service` CLI (not `launchctl` directly)", so a raw
`launchctl` line would contradict it. Verified with the throwaway label: unload
kills a run in progress, and load then does not start a job without RunAtLoad.

An option, not verified: make `_ENSURE_SERVICES` unload, then load, a label that
is already loaded (the earlier server-check critique recommended this too). It
may seldom fire after an Edit, because rcs-sync relinks a split plist first, and
then the inode matches. Also consider the `status is-interactive` guard, as
rcs-sync has. Then an agent's `fish -c` no longer loads an unfinished plist. The
cost is that a new plist waits for the user's next terminal.

## 3. Search for a script's callers before you delete it: CHANGED

The diagnosis is two misses, not one. The retired files were
`~/private/pancia/_bin/pinterest_save` (with `gallery-dl-config.json`) and
`~/Cloud/Media/wolfie/_sync.fish`.

- **Wrong search term.** The Hermes entry was
  `cd ~/private/pancia && _bin/pinterest_save`. It has no "wolfie". A search for
  the full path misses it too. Only the file's base name finds it.
- **Wrong search roots.** The vault `cmds.rb` contained "wolfie" and
  `./_sync.fish`, so it was outside the folders searched.

The proposed list of four places is incomplete. It misses `services/*` (plists and
scripts), `fish/functions` and `fish/conf.d`, `lib/lua` (Hammerspoon),
`rcs/karabiner.json`, `vpc/*.vpc`, hooks in `rcs/claude-settings.json`,
`~/AKR/scripts` and `tools` (where the `q` registry points), `~/Vaults/music`, and
the crontab (it has one entry). A list of folders will also go stale.

**Revised line**, for the "File Deletion" section of `rcs/claude-user-claude.md`
(the source; `rcs/MANIFEST` line 9 hardlinks it to `~/.claude/CLAUDE.md`, same
inode verified):

"Before you move or delete a script, search for its file name, not its topic or
its full path: `rg -l -F --hidden <name> ~/dotfiles ~/Vaults ~/.config
~/Library/LaunchAgents`, and check `crontab -l`. Callers often `cd` first and use
a relative path."

That search took 0.46 s with `--hidden`. It covers all four named places, because
`~/.config/q`, `~/dotfiles/cmds`, `rcs/hermes-commands.json` and
`~/Vaults/work-config/fs-config` are inside those roots. Positive control: with
`media-sync` as the name, it listed `rcs/hermes-commands.json`, the work-config
wolfie `cmds.rb`, `~/.config/q/media-sync` and `~/.config/q/pinterest`, both
copies of the plist, and the AKR script and sources.

## 4. One test notification at a time: CHANGED (wording and place)

The cause in the code is already fixed. In `services/media-sync/script.sh` the
failure notice has no `-group` and first removes the "Started" notice. So a later
notice can no longer replace it. Only the agent-behaviour line is left to judge.

The line is concrete and checkable, so it is likely to change behaviour. But its
trigger is weak. An agent that is "testing notifications" does not think "the
user must look at this by eye". Name the action instead, and add the mechanism
that caused the loss:

"When you send a test notification, or anything else I must check by eye, send
one at a time. Say its title and wait for my answer before the next. Give each
test notice its own `-group`, or none, so it cannot replace one I have not seen."

Put it next to "Pages that play sound", which is the same kind of rule (a check
only the user can make). A shared heading such as "Checks I make by eye or ear"
would hold both. Do not put it under "Reporting Back".

## 5. `service wait <name>`: CHANGED (design below, plus a defect it depends on)

Detection works. `bin/service` reads the PID column of `launchctl list`. For one
label, `launchctl list <label>` has a `"PID" = N;` line only while the job runs.
Probe with a throwaway job: the PID was present at the first check right after
`launchctl start`, and gone within 0.5 s of the end. `LastExitStatus` there is the
raw wait status: exit 3 showed as 768. The table form of `launchctl list` decodes
it to 3.

**A worse defect blocks exit-status reporting.** `bin/service-wrapper` runs
`exec "${@:2}" 2>&1 | ts ...` without `pipefail`, so the job's exit code is `ts`'s.
Verified: a job that exits 3 makes the wrapper exit 0. 21 service scripts use the
wrapper, media-sync included. So launchd records 0 for every failed run. Add
`set -o pipefail` to the wrapper. Verified on a scratch copy: with it, the same
job gives exit 3, and a job that succeeds still gives 0. The two plists with `KeepAlive {SuccessfulExit}`
(inari-cc, sanctuary-app) do not use the wrapper, so restart behaviour does not
change.

A related defect in `service status`: the label is inverted. A running job whose
last run failed shows "error (N)", and a stopped job always shows "stopped". So a
failed scheduled run is never visible, even after the wrapper fix. Show
"error (N)" for a stopped job with a non-zero last exit.

**Smallest sound design**, about 30 lines of Ruby:

`service wait <name> [--timeout SECS]`

1. Not installed, or `launchd_loaded?` false: print why, exit 3.
2. Read the PID from `launchctl list <label>`. None: print "not running", exit 2
   at once. Do not wait for a start; the probe showed no gap after `start`.
3. Poll every 2 s. The run has ended when the PID is gone or differs from the
   first one (a new run counts as the end of the old one).
4. On the end, read `LastExitStatus`, decode it (`>> 8` for the exit code, low 7
   bits for a signal), and print it. Exit 0 for 0, exit 1 for anything else. This
   is only true after the wrapper gets `pipefail`, so ship both together.
5. Timeout: exit 124 (as `timeout` and `claude-p` use) with "still running, pid N".
   Default 110 s, so a plain Bash call with its 120 s default timeout gets a clean
   124 rather than a kill. Re-run to keep waiting. For a long run, use
   `--timeout 3600` with `run_in_background`, which reports when it exits.

Why a subcommand and not a documented one-line loop on the `"PID"` key: the loop
is short, but each agent must also get the timeout, the 124 code, the PID-change
case and the status decode right. The session wrote its own loop twice, and each
one tailed a log instead. The global CLAUDE.md also says to use `service`, not raw
`launchctl`.

It only reads, so a kill of `wait` itself is harmless. Add a line to the
`service` docs in the global CLAUDE.md and `docs/services.md`.

## Side finding

`tests/bin/cc-peers/test_cc_peers.py` exists and `CLAUDE.md` cites it, but
`bin/cc-peers` is not in `COMPONENTS` in `lib/python/run_tests.py`. So the full
`cmds test` run never runs it. That is the silent rot the COMPONENTS rule exists
to stop.
