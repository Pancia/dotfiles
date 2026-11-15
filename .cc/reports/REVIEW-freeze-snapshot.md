# Review: freeze-logger and the root freeze-snapshot daemon

Date: 2026-11-13
Scope: `services/freeze-logger/script.sh`, `services/freeze-logger/root/freeze-snapshot.sh`,
`services/freeze-logger/root/install.sh`, `services/freeze-logger/root/org.pancia.freeze-snapshot.plist.in`.
Background: `.cc/reports/REPORT-mac-freezes-2026-11.md`.

Nothing was installed, restarted or run as root. Both scripts were run from a
scratch copy, with `PATH`, `OUT`, `HOME` and the timings substituted, a fake `ps`
that hangs while a flag file exists, and a fake `tailspin`.

## Summary

The bash logic is correct. Every suspect named in the brief checked out clean
(see "Checked and clean" below). The scripts start at most one stuck `ps` and at
most one `tailspin save` per hang, so they cannot pile up processes.

The real risk is in the design, and it is not provable without a real freeze:
the trace may be empty or useless. `tailspin save` may block on the same lock,
and by the time it runs, the ring buffer may no longer hold the moment the lock
was taken. One correctness bug exists (pid reuse can make the root watcher stop
for good, silently). `install.sh` has three small robustness issues.

## 1. Design risks (unverified, highest impact)

### 1a. `tailspin save` may itself hang
`tailspin save` writes the ktrace thread map and per-process data (names, UUIDs,
image lists). `-n` skips only symbolication. If it gets that data by walking the
process list, as `ps`, `lsof` and `sysmond` do, it blocks on the same wait event.
The script then logs "still running after 180s" and the file stays empty or
partial. The freeze report already lists this as unproven. Nothing in the code
can fix it, but two things reduce the cost:

- Before relying on it, run once by hand on a healthy machine:
  `sudo tailspin save -n -l 300 /tmp/t.tailspin`, then `tailspin stat /tmp/t.tailspin`.
  This shows how long a save takes, how big it is, and how many seconds it
  really covers.
- Optional fallback: a pre-emptive save while the machine is still healthy, for
  example when load passes a threshold, keeping the last one or two. A save
  taken just before the hang is the only trace that survives if every save after
  the hang blocks.

### 1b. The ring buffer may no longer hold the onset
Detection takes up to `INTERVAL + WAIT` = 30 s after the first stuck listing.
The newborn may have stuck even earlier. During the 11-13 freeze the machine ran
for 27 more minutes, with load near 195, and tailspin keeps recording the whole
time. The default buffer is a few tens of MB. Under a Go test burst with heavy
fork/exec, that can wrap in well under 30 s. `-l 300` only limits the trace; it
cannot add history the buffer no longer holds.

- After `tailspin enable`, read the buffer size from `tailspin info` and raise it
  with `tailspin set buffer-size <MB>` (in `install.sh`).
- Shorten detection: `INTERVAL=5`, `WAIT=5` costs one `ps` every 5 s as root,
  which is cheap. A slow `ps` under heavy load gives a false trace at most once
  per 30 min, which is still useful data.
- In `save_trace`, start `tailspin save` first and write the log line after.
  The `log` line forks `date` before the save. That costs only milliseconds, but
  it costs nothing to reorder.

### 1c. Do forks still work during the freeze? Evidence says yes
The brief says a newly forked child also blocks. If every fork blocked, both
scripts would hang at their next `sleep`, `date` or `/bin/kill` fork, before
any trace. The 11-13 stackshot
(`/Library/Logs/DiagnosticReports/forceReset-full-2026-11-13-181807.0002.diag`)
argues against that:

- It holds **76 `ps` processes**, all with positive pids (forked, published and
  exec'd). All are in `TH_WAIT|TH_UNINT` on the same wait event as the one
  newborn (pid -66421, `alt-54debd9d`). They blocked in the listing call, not in
  fork.
- One `sleep` process is in an ordinary interruptible wait (`TH_WAIT`, not
  `TH_UNINT`).

So fork and exec mostly worked during the freeze; only the process walk blocked.
The scripts' extra forks are therefore a low risk. The builtin `kill` (see 4d)
and a fork-free sleep (`read -t N` on an open fifo works in bash 3.2) would
remove the dependency entirely, if wanted.

Side note on the freeze report: it says the 76 `ps` were "the logger's own, every
30 s". The old logger ran `ps` in the foreground and its log stops at 17:51:08,
so it can have made only one. Something else started the other 75. It may be
worth finding out what, because that something also keeps polling the process
list.

## 2. Correctness bug

### 2a. Root watcher: pid reuse can stop all checks for good (Medium)
`freeze-snapshot.sh` line 66: `kill -0 "$stuck"`. As root, `kill -0` succeeds
for **any** live pid. Bash reaps the stuck `ps` as soon as it ends. If its pid is
reused before the next check (20 s later), `stuck` stays set while that new
process lives. Then no listing runs, no "returned again" line is written, and no
later hang is ever detected. Pid wrap is real here: the 11-13 stackshot pids span
5803 to 98651 after a wrap, under heavy fork/exec.

Fix: ask bash's job table, which knows its own children and is immune to reuse.
Checked in `/bin/bash` 3.2:

```bash
case " $(jobs -rp | tr '\n' ' ') " in
    *" $stuck "*) ;;                                   # still running
    *) log "process listing returned again"; stuck="" ;;
esac
```

The user logger has the same pattern (`script.sh` line 26), but there `kill -0`
fails with EPERM for another user's process. The window is smaller, but the same
fix applies.

## 3. install.sh (Low to Medium)

- **bootout then immediate bootstrap can race on a reinstall.** `launchctl bootout`
  can return before the job is fully gone, and `bootstrap` then fails
  ("Bootstrap failed: 5: Input/output error"). Under `set -e` that aborts with the
  daemon not loaded until the next boot. Unverified here. Fix: after bootout, loop
  up to ~10 s while `launchctl print system/$LABEL` still succeeds.
- **Diagnostic lines can fail a good install.** Lines 35-36 run under `set -e`.
  If `grep` finds no `state`/`pid` line, or `watch.log` does not exist yet after
  `sleep 2`, the script exits non-zero after everything worked. Add `|| true` to
  both. (The grep pattern itself is fine: it matches launchd's tab-indented
  `state = running`.)
- **It trusts the user-writable checkout at the moment of `sudo`.** The installed
  copy is root-owned, which is correct. But this repo is a shared working copy
  that several Claude sessions edit at once. Whatever `freeze-snapshot.sh` holds
  at that moment becomes root code. Cheap guard: print `shasum -a 256` and a
  `diff` against the installed `$BIN`, then ask y/N before copying. Better:
  install from a committed revision (`jj file show -r <rev> ...`).
- **`/usr/local` ownership is assumed.** It is `root:wheel 755` on this Mac.
  `install -d -o root` fixes `/usr/local/sbin` itself, but on an Intel Homebrew
  layout `/usr/local` subfolders are user-owned. A check would refuse such a
  layout: `[ "$(stat -f %Su /usr/local)" = root ] && [ ! -L /usr/local/sbin ]`.

## 4. Low

- **4a. A second `tailspin save` can start while one is still stuck.** If a save
  passes `SAVE_WAIT`, then `ps` recovers and hangs again over 30 min later, a
  second save starts. This is bounded at one per `GAP`. Optional: keep `$t` and
  skip the save while `jobs -rp` still lists it.
- **4b. Traces are world-readable.** The folder is 755, and the files take the
  default umask. A kernel trace holds every process name and syscall, with file
  paths. On a single-user Mac this is minor. Use `750 root:admin` if wanted.
- **4c. Plist has no `ProcessType`.** Without one, launchd applies light CPU/IO
  throttling. Under load near 195, a throttled save is slower and the buffer
  wraps further. `ProcessType` `Interactive` removes the throttling.
- **4d. `script.sh` forks `/bin/kill` and `/bin/sleep` up to 10 times per
  sample.** The builtin `kill` does the same syscall without a fork.
- **4e. `PS_STUCK_AT` is the detection time, not the start time.** "Stuck since
  20:03:21" for a `ps` started at 20:03:19. Set it to the sample's time before
  starting `ps`, or reword the line to "detected at".
- **4f. `tailspin info` check: match the string that was seen.** Only the disabled
  output was seen here (`tailspin has been disabled (default behavior)`, on
  stdout). The enabled wording was never seen, so `grep -q enabled` could warn
  falsely. `grep -q disabled` matches the observed text.
- **4g. Log folder deleted later.** `install.sh` creates
  `/Library/Logs/freeze-snapshot` before bootstrap, so the first start is fine.
  If someone later deletes it, launchd may fail to open `StandardOutPath` at the
  next boot. The script's own `mkdir -p` helps only once it runs. Unlikely.
- **4h. `sync` after the save can be slow.** In the test it delayed the next check
  by about 5 s. Keep it, because unflushed data would be lost at a power-button
  reset, but log a line after it so the delay is visible.
- **4i. No tests.** The scratch harness used here (sed the `PATH`/`OUT`/timings,
  fake `ps` gated on a flag file, fake `tailspin`) could become
  `tests/services/freeze_logger/`, registered in `COMPONENTS` like `server_check`.

## Checked and clean

| Suspect | Result | Evidence |
|---|---|---|
| State set inside `sample` survives `sample >>file` | Survives | A redirect on a function call does not make a subshell. Tested in `/bin/bash` 3.2; the harness showed `HUNG ... still stuck` then `RECOVERED` across samples. |
| `kill -0` on an exited, unwaited child | Reports gone | Bash 3.2 reaps background children on SIGCHLD; both builtin and `/bin/kill` report gone. |
| `wait` on a stuck pid | Never happens | Both scripts call `wait` only after `ended_within` / the poll loop saw the pid end. |
| `$?` in `log "tailspin save exited $? ($(du ...))"` | Correct | Expansion runs left to right; a test printed `exited 3` for a child that exited 3. |
| Retention loop | Correct | With `KEEP=2`, four saves left the two newest. Names are root-made with no spaces. |
| `grep -q enabled` matching "disabled" | No match | "disabled" does not contain "enabled". See 4f for the real gap. |
| `tailspin save -n -r -l` on macOS 15.7.4 | Valid | All three are in `tailspin help`. |
| `_ENSURE_SERVICES` claim | True | `find $HOME/dotfiles/services -type f -name '*.plist'` is recursive, so a `root/*.plist` would be hardlinked into `~/Library/LaunchAgents` and loaded as a user agent. `.plist.in` does not match. `bin/service` looks only at `services/<name>/<label>.plist`. |
| Plist with a comment before the DOCTYPE | Valid | `plutil -lint` on a copy: OK. |
| Root PATH, symlinks in the log folder | Safe | `PATH` is fixed. `/Library/Logs` and `/usr/local` are root-owned 755, so a user cannot plant a symlink or replace the binary. launchd gives the daemon a clean environment. |
| Process pile-up during a real freeze | None | At most one stuck `ps` per watcher. No new listing while one is stuck. At most one save per 30 min. Shown with the fake hanging `ps`. |

## Effort

Items 2a, 3 (first two), 4d, 4e and 4f: about 30 minutes. Item 1b (buffer size,
shorter timings): 15 minutes plus one manual `tailspin save` to measure coverage.
Item 1a's fallback (pre-emptive save) is a design choice, about 1 hour.
