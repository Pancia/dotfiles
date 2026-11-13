# Critique: retro suggestions from the server-check session

Date: 2026-11-12. Read-only review. Behaviour tests ran only in scratch copies
and with one throwaway launchd label (`test.critique.loadtwice`, unloaded after).
Nothing in ~/dotfiles or ~/AKR was changed except this file.

## 1. SERVER_CHECK_STATE override plus a test: CHANGED

The diagnosis is true. Every command in `services/server-check/script.sh` uses an
absolute path (`/usr/bin/ssh`, `/opt/homebrew/bin/timeout`, `/usr/bin/nc`), so a
PATH stub cannot fake anything. Editing a copy was the only way in.

The fix works, with three changes. I tried it on a scratch copy:

- **Skip the internet check when the state is faked.** Without that, the test
  depends on the network. Offline, every case exits 0 with "no internet; skipped".
  The `ok` case then fails, but each problem case fails too, so the suite turns
  red offline. Both the ssh call and the `nc` check exist only to talk to the real
  network, so one knob that replaces both is reasonable.
- **Test with `${SERVER_CHECK_STATE+x}`, not `${SERVER_CHECK_STATE:-}`.** An empty
  state must be allowed, because that is how the test reaches "server unreachable".
- **No new knob is needed for curl.** `SERVER_CHECK_URL=file://$tmp/health`, with
  the file holding `pass` (or missing), works through `curl -fsS` with no network.
  Verified.

Results on the scratch copy, all with `SERVER_CHECK_DRY=1` and
`SERVER_CHECK_RETRY_DELAY=0`: `reachable musicdisk navidrome` gives ok; adding
`unlocked` gives the unlocked warning; dropping `musicdisk` gives "music disk not
mounted"; dropping `navidrome` gives "Navidrome is not answering"; an empty state
gives "SSH: server unreachable"; a missing health file gives "Headscale or its
certificate".

The test must always set two things, or it does harm:

- `SERVER_CHECK_DRY=1`. Without it, every problem case sends a real macOS
  notification. Put both in one fixture so no case can forget them.
- `SERVER_CHECK_RETRY_DELAY=0`. Otherwise each problem case sleeps 120 s. This
  variable is also missing from the script's header comment, so add it there.

**Drift check: keep it static.** Parse `problems+=("...")` from script.sh and the
`== *"..."*` patterns from show.sh. Check both ways: each message contains some
pattern, and each pattern is inside some message. The reverse direction catches
stale help. Today there is no drift: all 5 messages and 5 patterns match. Do not
run show.sh in a test. It ends with `exec /opt/homebrew/bin/fish -l`, and
`fish/config.fish` runs `_ENSURE_SERVICES` on every fish start, including
non-interactive ones. That relinks plists and runs `launchctl load` on the real
LaunchAgents. If a dynamic check is ever wanted, first add an env knob that skips
the final exec.

**What the test cannot cover.** The state words (`reachable`, `musicdisk`,
`navidrome`, `unlocked`) are a contract with `/usr/local/bin/server-health` on the
server. That script is not in the repo, so a faked state pins only the Mac half.
Name the four words in a comment next to the greps. A static string also cannot
test the "fails once, passes on retry" path. That is acceptable.

Smaller defect in the same code: the greps are bare substrings. `grep -q
reachable` also matches `unreachable`. `grep -qw` closes that cheaply.

**Where the test lives.** Use `tests/services/server_check/test_server_check.py`,
with an `__init__.py` (tests/services has one). Register it in `COMPONENTS` in
`lib/python/run_tests.py`:
`"services/server_check": {"runner": "pytest", "deps": [], "aliases": ["server-check"], "source_path": "services/server-check"}`.
Without that entry it never runs. `tests/hooks` already holds
`test_cc_transcript_backup.py` for a service script, so it would run there with no
registration. But "hooks" is the wrong label, and that file is a precedent to fix,
not to copy.

## 2. `service start` skips `launchctl load` when loaded: CHANGED

Reproduced with a throwaway label. Loading an already-loaded plist prints `Load
failed: 5: Input/output error` and the bootstrap hint, and **exits 0**. So the fix
cannot rely on load's exit code. Checking `launchctl list <label>` first works: it
exits 0 when loaded and 113 when not.

The claim about `restart` is wrong. `restart` runs stop, then unload, then load,
then start. The label is gone by the time load runs, so it never prints this
message. Leave `restart` as it is: unload then load is also what makes launchd
re-read an edited plist.

A worse defect sits next to this one. `execute` returns the result of `system`,
and no caller reads it. `launchctl start` on an unknown label exits 3, and the
script still prints "Started". Revised fix for `start`:

- If `launchctl list <label>` exits 0, skip load.
- Otherwise load, then confirm with `launchctl list <label>`. Load's exit code
  means nothing here.
- Check the exit code of `launchctl start`, and print "Started" only on 0.
  Otherwise print an error and exit non-zero.

Nothing depends on the current noise. Hermes runs `service start <name>` as a
plain command and ignores its output.

A worse defect, outside this command: `_ENSURE_SERVICES` in `fish/config.fish`
"(re)loads" a plist whose inode changed, with a bare `launchctl load`. For a job
that is already loaded, that load fails silently (exit 0). Verified: after editing
the plist and loading again, launchd still ran the old program arguments. So an
edited plist does not take effect until someone runs `service restart`. The
`rcs-sync` path already reminds the user to restart. The fish startup path prints
"(re)loading" and changes nothing. The fix is unload, then load, for a label that
is already loaded. Do not add `start` back: commit 1857dd9e removed it on purpose,
so that a scheduled job does not run on every plist edit.

## 3. Exclude `.cc/pending-updates-*.md` from the exit-5 stop: CHANGED

The diagnosis is confirmed, and the cause is structural, not chance. Each window
runs from the previous Bash call's id to this one, and the windows are contiguous.
So the coverage for each session runs from its first Bash call to its last, and
holds **every** write to the working copy in that time. `ccjj who` on the file
shows three live sessions with a "window only" stake on it, this one included.
Each of them stops with exit 5 the next time it commits. The refusal text then
tells each one to `ccjj claim` a file that none of them wrote.

ccjj has no exclusion list. The only filters are `peer_record_paths` (paths with a
peer's journal records), the `still` test, `--also` and offers. After
`--no-claim`, the path becomes an offer, so the stop happens at most once per
session per file. But it happens in every live session.

The design does not argue against a fix. The docs record three earlier false-stop
classes that "trained agents to pass --no-claim", and the code fixed each one. A
false stop is exactly what the design treats as harm. But a filename glob inside
ccjj is the wrong place for the fix. It ties ccjj to another tool's naming, and it
covers one writer only.

**Revised fix, smallest first:**

1. **Ignore the file in VCS.** Add `.cc/pending-updates-*.md` to
   `git/gitignore_global`. jj reads `core.excludesFile`; I verified the pattern in
   a scratch jj repo. These files are a per-machine queue: `/cc:pending-updates`
   applies each one and then deletes it. Today they ride along in unrelated
   commits. History shows them in "Add svc suspend/resume", "Harden AI commit
   pipeline" and others, each later removed by an "Apply ... updates" commit. The
   repo is public, and each file names a session id. Ignoring them removes the
   false stop for every session and in every repo at once. Costs:
   - Run `jj file untrack` once on the file that is tracked now, because an
     ignore rule does not untrack it.
   - Update step 5 of `ai/commands/pending-updates.md`. It commits "deleted
     pending-update files", and with the ignore there is nothing to commit for
     them.
   - Fix a defect in the same step: `jj split -r @ CLAUDE.md .cc/` takes every
     change under `.cc/`, including other sessions' reports. Split `CLAUDE.md`
     only.
2. **The general fix, if other background writers matter.** Let a non-session
   writer leave a journal stake under a pseudo-session, for example
   `ccjj note-foreign <path>`. Then `peer_record_paths` excludes the path through
   the mechanism the doc already describes ("a path only a peer has records on").
   Candidates: `cc-session-review`, `ccsave`, the `rcs-sync` adopt-into-repo
   writes, and apps that save to a hardlinked file. No glob can cover the `rcs-sync`
   adopt case, because it can hit any MANIFEST file. Do this only if a second
   writer causes a false stop. Option 1 covers the case that actually happened.

## 4. Global CLAUDE.md rule about security controls: CHANGED

The situation is concrete enough: an alert that tells the user to unlock, disable
or open a security control. The action is not. "Ask whether the design needs that"
reads as "ask the user a question". That clashes with the file's own rules: "Give
your recommendation if you have one" and "Do not invent an ask". It also adds a
round trip. In the session, the right answer did not need a question: say what the
unlock exposes, and propose a change so the automation works with the control on.

The rule also misses the earlier failure. A previous session built a backup that
needed the disk unlocked, and wrote an alert telling the user to unlock it. A rule
about reacting to alerts does not cover designing automation, or writing such an
alert.

Revised wording:

> When automation needs a security control off to keep working (an unlocked disk,
> a disabled check, an open port), do not tell me to turn it off. Say what that
> exposes, and propose a change so it works with the control on. The same applies
> when you design the automation or write its alerts.

It conflicts with nothing in the file. A real choice still becomes a Q-numbered
question under the existing rules, and the reply stays within the word limits.

Placement: its own short section, `## Security trade-offs`, before
`## File Deletion`. It is a judgement rule, like File Deletion. "Reporting Back"
is about format only. The edit target is `rcs/claude-user-claude.md` (hardlinked
to `~/.claude/CLAUDE.md`; the ensure-rcs hook blocks edits to the destination).
That file holds a peer session's uncommitted edit (a new "Pages that play sound"
section). Commit with `commit-mine` so that edit stays out.
