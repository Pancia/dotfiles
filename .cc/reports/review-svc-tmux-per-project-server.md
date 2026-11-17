# Review: svc-tmux per-project tmux server + ClaudeCode.app refusal

Date: 2026-11-17. Scope: uncommitted hunks in `bin/svc-tmux`, `tests/svc/test_svc.py`,
`wiki/pages/supervise-svc.md`, `CLAUDE.md` (~330), `rcs/claude-user-claude.md` (~327),
`lib/svc/tmux.conf` (header). No file other than this report was changed.

Status (same day): findings 1-6 and 8-10 are fixed in the same commit as this
report. Finding 7 was skipped by choice. The vault `cmds.rb` wording (finding 10)
was left for the user. Suite: 31 passed, also when run as a background session.

## What was checked

- Read every hunk and the whole of `bin/svc-tmux`.
- Test suite as briefed: 25 passed (53 s), run from an iTerm2-owned session.
- Same tmux tests with `SVC_TMUX_FAKE_RESPONSIBLE=<ClaudeCode.app path>` in the outer
  env, to act like a Claude background session: 6 failed (finding 4).
- Probe on this machine: `responsibility_get_pid_responsible_for_pid` returns iTerm2
  (pid 672) for this session; it takes about 27 ms. `ps -o comm= -p 32688` (the
  background-session host) prints the ClaudeCode.app path.
- Socket name limit: throwaway servers `zzlen...` work up to 81 characters and fail
  at 82 with "File name too long". `svc-tmux up` in a scratch project whose folder
  name has 72 characters fails (finding 3).
- Live tmux servers were only listed, never changed. The old shared `svc` server
  still hosts `svc-3d-vr-scene-experiment-200424` (finding 2).
- Searched `~/dotfiles`, `~/Vaults/work-config`, `~/.config`, `~/projects`,
  hammerspoon and fish for `tmux -L svc`, `-L svc`, `SVC_TMUX_SOCKET` and readers of
  `.run/tmux-session`. Nothing outside svc-tmux and its tests depends on the old
  socket name. `svc`, `supervise`, the status-right hook and the festivar `cmds.rb`
  (`svc-tmux up; and svc-tmux attach`) work unchanged.

## Findings, most severe first

### 1. `up` refuses even when it would create no server; the join check also has a race (confirmed)

`bin/svc-tmux:195` calls `check_server_owner` before the loop, so it fires when no
per-project server runs, even if `up` would create nothing. Example: a service already
runs in a plain `cmds` pane, or in the old shared `svc` server. `up --wait` from a
background session then exits 1 with the refusal, instead of "running elsewhere" and a
readiness wait. Finding 4 shows this:
`test_up_and_down_leave_an_outside_instance_alone` fails on the refusal. This
contradicts the wiki line "Idempotent: `up` skips a service that runs anywhere".

There is also a check-then-act gap. `down` takes no lock. The check sees a running
server ("join is fine"). A concurrent `down` (or the last window exiting) then ends the
server. `new_window` then makes a new server from ClaudeCode.app, with no guard. The
window for this is narrow.

Fix: move the check to the place where a server is created. That is the no-session
branch of `new_window` (`bin/svc-tmux:120-131`), right before `tmux new-session`, and
inside the existing lock. Then nothing is refused when nothing is created, and the
check sits next to the action it guards. Keep the test as "no server runs"
(`TM list-sessions`), not only "no session": with a shared `SVC_TMUX_SOCKET`, a
second project has no session but joins a running server.

### 2. A project still on the old shared `svc` server becomes invisible to `attach`, `down` and `ls` (confirmed by reading; one live case now)

`bin/svc-tmux:47` no longer looks at `tmux -L svc`. Live now:
`svc-3d-vr-scene-experiment-200424` on the old `svc` server. In that project:

- `svc-tmux ls` prints "no session for this project" and marks the services `[elsewhere]`.
- `svc-tmux attach` says "no session for this project - svc-tmux up first". But `up`
  prints "running elsewhere - left alone" and creates nothing, so this advice does not
  help.
- `svc-tmux down` says "runs outside this session - not stopped (svc stop X)".

Nothing breaks, and `svc stop` for each service drains the old server. But the message
gives no way to reach the old session. This state lasts as long as the old server runs,
which can be days.

Fix (pick one): (a) when `SVC_TMUX_SOCKET` is unset and `tmux -L svc has-session -t "=$S"`
succeeds, use `SOCK=svc` for this run, so all commands keep working until `down`; or
(b) at least print one line in `ls`, `attach` and `up`: "this project's session is on
the old shared server: `tmux -L svc attach -t =$S`, or `svc-tmux down` + `svc stop` to
move it". (a) is simpler for the user. Its cost: that project keeps the old server's
env and privacy access until `down`, which is how things work today anyway.

### 3. A project folder name longer than 70 characters cannot use svc-tmux at all (confirmed)

`bin/svc-tmux:47`: `SOCK=$S`, and `S` holds the whole cleaned folder name. A Unix
socket path on macOS is limited to 104 bytes. tmux puts sockets in
`/private/tmp/tmux-501/`, so the name can have at most 81 characters. `S` is the folder
name plus 11. In a scratch folder with a 72-character name, `up` printed
`error connecting to ... (File name too long)` and then the misleading
`could not create tmux session`. `ls` and `attach` say "no session". Before this change
only the session name held the long name, and that has no such limit. A long
`TMUX_TMPDIR` makes the limit lower.

Fix: shorten only the socket name, not the session name, so existing sessions stay
valid. For example: `base=...; SOCK="${SVC_TMUX_SOCKET:-svc-${base:0:40}-$hash}"`. The
hash already keeps names unique. Update the header comment and wiki ("same name as
the session") to match.

### 4. The test suite fails when it runs from a Claude background session (confirmed)

`tests/svc/test_svc.py:488-499` (`tmux_env` fixture) copies `os.environ` and does not
set `SVC_TMUX_FAKE_RESPONSIBLE` or `SVC_TMUX_ALLOW_ANY_APP`. So every svc-tmux test
uses the real probe. From a background session the probe returns ClaudeCode.app and
`up` refuses. Reproduced: 6 failures (`test_svc_tmux_windows_find_a_logically_keyed_vault_conf`,
`test_colliding_project_names_stay_separate`,
`test_up_wait_is_idempotent_clean_env_and_down`, `test_concurrent_ups_make_one_window_per_service`,
`test_up_wait_reports_a_dead_pane`, `test_up_and_down_leave_an_outside_instance_alone`).
An LLM or a pre-commit hook that runs `cmds test svc` from a background session gets a
red suite.

Fix: in `tmux_env`, set `SVC_TMUX_FAKE_RESPONSIBLE="/Applications/iTerm.app/Contents/MacOS/iTerm2"`
(a neutral app). The refusal test already overrides it with the ClaudeCode path. Do not
use `SVC_TMUX_ALLOW_ANY_APP=1` in the fixture; the refusal test would then need to
remove it.

### 5. The refusal message invites an LLM to bypass the guard; LLM docs say nothing about it

`bin/svc-tmux:103-104` ends with "(or set SVC_TMUX_ALLOW_ANY_APP=1 if no service reads
those folders)". The caller that hits this refusal is almost always an LLM in a
background session. It cannot know whether a service reads ProtonDrive, and it tends
to set the variable and retry. The LLM-facing rules do not cover the refusal:
`rcs/claude-user-claude.md:351-355` and `docs/claude-global/background-processes.md:34-38`
still say "To start one, an LLM uses `svc-tmux up --wait <name>`". The "LLM contract" in
`wiki/pages/supervise-svc.md` (~line 213) is the same.

Fix: in the message, say "If you are an LLM: stop and ask the user to run `svc-tmux up`
in a terminal; do not set SVC_TMUX_ALLOW_ANY_APP yourself." Add one sentence with the
same rule to the three LLM-facing places. Note: `rcs/claude-user-claude.md` is
`~/.claude/CLAUDE.md`, so adding text there costs tokens in every session (about 30
input tokens for one sentence). `docs/claude-global/background-processes.md` and the
wiki cost nothing per reply.

### 6. Detection depends on argv[0] of the responsible process (partly a guess)

`bin/svc-tmux:88` uses `ps -o comm=`. On macOS this prints argv[0] as the program was
started, not the real executable. Today the host (pid 32688) was started as
`.../ClaudeCode.app/Contents/MacOS/claude --bg-pty-host ...`, so the pattern matches.
But:

- `proc_pidpath(32688)` returns `/Users/anthony/.local/share/claude/versions/2.1.326`.
  `ClaudeCode.app/Contents/MacOS/claude` is a hard link to that file (same inode,
  844175082). `proc_pidpath` returns the same path for this foreground session's
  claude process (pid 80666). So the real path cannot tell a background host from a
  foreground session. Do not use it as a signal.
- Claude session processes already rename themselves. This session's process shows as
  `claude [festivar-webapp 15:34:50]` in `ps -o comm=`. If a later version renames the
  host the same way, the pattern stops matching and the guard lets everything through
  with no message. (Guess: no such change has been seen for the host.)

Fix: keep the `comm` match. When the probe returns nothing (private symbol missing,
python missing), print one stderr line such as "svc-tmux: could not check which app
owns this process". Then a silent pass is visible. An optional second signal, not
verified: the responsible pid's `ps -o command=` contains `--bg-pty-host`. That also
reads argv, so a rename would defeat it too. Do not match on
`.local/share/claude/versions/`: it would also refuse a plain CLI `claude` that is its
own responsible process (for example, one started directly by launchd).

### 7. The guard blocks one bad app, and joining an already bad server gives no warning (design point)

Other callers whose processes lack the folder grants still pass with no message:
launchd agents, cron, and possibly ssh sessions or the Claude desktop app. That last
one is a guess; I did not test it. Separately, "joining is fine" assumes the running
server is healthy. A server created before this change, or with
`SVC_TMUX_ALLOW_ANY_APP=1`, may already belong to ClaudeCode.app. A later `up` from
iTerm then adds services to that server, and they get EPERM with no hint.

Fix: when the server is created, store its responsible app in a tmux user option, for
example `tmux set -g @svc_owner_app "$app"`. `ls` and `up` then show it, and `up` warns
if it is not a terminal app. A full allowlist (iTerm2, Terminal) is stricter, but it
would refuse the launchd and ssh cases, which may be legitimate. So treat that as your
choice, not a fix.

### 8. `/usr/bin/python3` on a Mac without the Command Line Tools opens an install dialog (guess, low)

`bin/svc-tmux:85`. Without the Command Line Tools, `/usr/bin/python3` is a stub that
opens a GUI install prompt and fails. The probe then fails open, which is correct, but
the user sees a dialog every time `up` creates a server. The tools are installed here,
so this only matters on a new machine. Fix: run the probe only if
`xcode-select -p >/dev/null 2>&1`, or use a different interpreter.

### 9. The tests do not cover the new default (confirmed)

Every svc-tmux test sets `SVC_TMUX_SOCKET` (`tests/svc/test_svc.py:493`), so no test
uses `SOCK=$S`, which is the main change. `test_colliding_project_names_stay_separate`
(~line 595) still puts two projects on one shared socket. That is the old model.
Smaller points about the new test (~line 532):

- The final `down` is not in a `finally` block. Fixture teardown kills the server, so
  nothing leaks.
- `tm(tmux_env, "ls") == ""` is also true when `ls` fails for some other reason. That
  is acceptable here.

Fix: add a test that removes `SVC_TMUX_SOCKET` from the env. It should check that two
projects get two servers, named by `svc-tmux session`. Clean up both sockets in
`finally`. Tests that are not about sharing should drop the shared-socket idea. A
long-name test belongs with finding 3.

### 10. Small doc points

- `lib/svc/tmux.conf:7-8` (not part of this diff) still says the plugins "would act on
  the svc server too". Make it "on each svc-tmux server".
- `wiki/pages/supervise-svc.md:174`: "`svc-tmux ls` prints it". `ls` prints the socket
  name only when a session exists; `svc-tmux session` always prints it.
- `wiki/pages/supervise-svc.md:197`: "Idempotent: `up` skips a service that runs
  anywhere". This holds again once finding 1 is fixed. Until then, add the caveat.
- `wiki/pages/supervise-svc.md:209`: "Server start costs ~3s ... once per server". This
  is still true, but now each project pays it once.
- `.cc/plans/PLAN-svc-tmux.md:65` still says `tmux -L svc`. The `bin/svc-tmux` header
  names that plan as the design, so add a dated line that says the server is now per
  project.
- The vault `cmds.rb:13` for festivar
  (`~/Vaults/work-config/fs-config/Users/anthony/projects/work/festivar-webapp/cmds.rb`)
  says "in the svc tmux server". Make it "in this project's svc-tmux server". Commit it
  in the vault.
- Each per-project server leaves its socket file in `/private/tmp/tmux-501` after it
  exits. One stale `svc-...-svc-sock-test-...` socket is there now. This is harmless,
  and a reboot clears it.
- The wiki text about the old `svc` server's history is accurate, and so is the
  `svc-tmux down` / `up` advice. The text in `CLAUDE.md:330` and
  `rcs/claude-user-claude.md:327` is accurate.

## What is sound

- `set -euo pipefail` handling in the new functions is correct. A python failure gives
  `|| return 0`. A non-numeric pid only prints an "integer expression expected" message
  and then reaches `|| true`. `die` inside `check_server_owner` exits through the EXIT
  trap, which removes `.run/svc-tmux.lock`.
- `TM list-sessions` does not start a server. Concurrent `up` calls in one project are
  ordered by `up_lock`. Because the server is now per project, that lock now covers
  server creation too.
- Session targeting with `=`, the env scrub, the status-right hook and `.run/tmux-session`
  are unaffected.
