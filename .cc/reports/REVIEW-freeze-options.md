# Review: Mac mini freezes, diagnosis and options

Date: 2026-11-14
Scope: `.cc/reports/REPORT-mac-freezes-2026-11.md`, `REVIEW-freeze-snapshot.md`,
`services/freeze-logger/` (user logger, root daemon, installer), the four
`forceReset-full-*.diag` stackshots, the two readable `.WindowServer-*.ips` watchdog
reports, the unified log, and `~/projects/altera`.

Nothing was installed, restarted or run with sudo. No `tailspin save` was run.
The only process I started for a test was a 5-second `taskpolicy -b sleep`.

## Summary

The stackshots already hold the answer. Tailspin is not needed to find it.

The hang is not a lock on the process list. Each of the four freezes is **one process that
deadlocks on itself in the middle of `exec`**:

1. Inside `exec`, `proc_exec_switch_task()` marks the process "exec in progress"
   (`proc_refdrain_will_exec`). Every `proc_find()` on that pid now waits until the
   exec ends (`proc_refwake_did_exec`).
2. Still inside that window, the same thread calls `ipc_importance_exec_switch_task()`.
   That call can recompute the task's scheduling policy. When the result changes the
   task's "background" state for sockets, it calls
   `proc_apply_task_networkbg(task_pid(task))`, which calls `proc_find(pid)` on **its own pid**.
3. `proc_find` sees the exec flag and waits for the exec to finish. Only this thread can
   finish the exec. The wait is uninterruptible. It can never end.
4. Every later caller that touches that pid waits for ever: `ps`, `lsof`, sysmond, iTerm2,
   and the parent when it exits. `runningboardd` blocks too, while it holds the global
   coalition-policy mutex. WindowServer then blocks on runningboardd, so the screen freezes.

All four stackshots show this, with the same frames. In all four, the stuck process belonged
to **iTerm2's resource coalition**. Every member of that coalition except iTerm2 itself was
"darwin background" (App Nap style suppression). `runningboardd` blocked on the same pid
**within 1 ms** of the exec thread, inside the system call `coalition_policy_set`. That call
switches background mode on or off for a whole app coalition.

So the likely trigger is a race. RunningBoard switches iTerm2's coalition **into** background
mode (App Nap suppression: iTerm2 hidden, behind other windows, or the display asleep). At the
same moment, a process inside that coalition is in the middle of `exec`. The direction comes
from the source. `coalition_policy_set` first updates every member's policy under the
coalition lock, then does the socket work, which is where it blocked. Every member was still
background at capture, so the switch it was making was "on". Altera, its
`go test` runs and the Claude sessions all run inside iTerm2's coalition, so they raise the
exec rate. That is why the freezes cluster around Altera work, but Altera is not the cause.
On 11-07 the stuck execs were `bash` starting `sed` and `readlink`.

The XProtect / Gatekeeper theory does not fit. The programs being exec'd were system
binaries (`sed`, `readlink`, `git`, `sh`), not new Go test binaries. syspolicyd,
XprotectService and amfid were idle in all four stackshots. The mitigations built on that
theory (Developer Tools permission, ad-hoc signing, reusing test binaries) would not help.

The deadlock path is unchanged in the newest public xnu (`xnu-12377.121.6`, macOS 26.x). I
compared `proc_exec_switch_task`, `ipc_importance_exec_switch_task`, `proc_find`,
`proc_ref_needs_wait_for_exec` and `proc_apply_task_networkbg`; all are identical.
`task_policy_update_complete_unlocked` only gained an App Nap memory-priority call *after* the
socket step. Apple has published no kernel source for 15.8.3, so whether it fixes this is
unknown. It is not a known fix.

## Ranked options (expected value first)

| # | Option | Kind | Cost | Expected value |
|---|---|---|---|---|
| 1 | Run the tmux servers (Altera, agents, `svc`) from launchd, not from an iTerm2 shell, so they live in their own coalition. Attach from iTerm2 as now. | prevent | 1-2 h; restarting tmux ends live sessions | High, and it does not depend on what makes RunningBoard flip the coalition. On 11-13 the 14 `ps` in a launchd-job coalition were *not* background, while all 60 in iTerm2's coalition were. It also stops tests running throttled while iTerm2 is in the background. Claude sessions started directly in iTerm2 tabs stay exposed. |
| 2 | Turn off App Nap for iTerm2 (`defaults write com.googlecode.iterm2 NSAppSleepDisabled -bool YES`, restart iTerm2). Verify with the `pri` check below. | prevent | 2 min, slightly more power | High, if App Nap is what flips the coalition. That is likely (RunningBoard logs App Nap assertions for iTerm2), not proven. Do it first as a quick test: if `pri` stays 31 with iTerm2 hidden, it covers everything in iTerm2, not just tmux. |
| 3 | Add two cheap probes to the user logger: the count of iTerm2-coalition processes at priority 4 (background), and iTerm2's coalition id. | detect | 20 min | Medium. The next freeze then shows whether a background flip came just before it. |
| 4 | A post-mortem script that does this review's analysis from a `forceReset` file: onset time, stuck pid, the old and new image, the coalition, the order of waiters, and a `log show` for that time window. | detect | 1 h | Medium. One freeze is analysed in seconds, not hours. |
| 5 | File a Feedback Assistant report with one stackshot and the call chain below. | fix upstream | 30 min | Medium long-term. This is a kernel self-deadlock, and only Apple can fix it. |
| 6 | Shrink tailspin to its default, or turn it off. | cost | 1 min | Gives back 256 MB of wired memory on a machine that swapped 1.8 GB on 11-13. The trace now adds little. |
| 7 | Reproduce the bug in a macOS 15.7.4 VM (design below). | confirm | half a day, plus 4 GB RAM while it runs | Medium. It proves the trigger and tests options 1 and 2 with no risk to the host. |
| 8 | Lower Altera's exec rate (`go test -p`, fewer parallel workers). | reduce | small | Low to medium. It only lowers the odds per flip. |
| 9 | macOS 15.8.3 | general | 30 min plus restart | Unknown for this bug (no source published; the macOS 26 source still has the path). Worth it for security fixes anyway. |
| — | Check every 2 s with a 3 s threshold (proposed earlier) | detect | — | Not worth it. The stackshot already gives the onset to the millisecond and names the stuck process. Faster detection only helps an early alert (section 2, item 4), and 3 s gives false alarms under load. Keep 5 s / 5 s. |
| — | Developer Tools permission, ad-hoc signing, reusing binaries | — | — | Do not do these. They target scans that were not happening. Developer Tools also turns off Gatekeeper and notarization checks for everything the terminal starts (see below). |

## 1. What the stackshots show

### Kernel frames can be named without a KDK

The kernel is not fully stripped: `nm` lists 6,566 exported symbols, and
`LC_FUNCTION_STARTS` gives every function start. Stackshot frame offsets are relative to
`__TEXT_EXEC` (`0xfffffe00072b8000` in `kernel.release.t8103`). That fits all the frames:
`0x7b88` lands in the exception vectors, `0x70f12c` in the system-call dispatcher, and
`0x5c0558` inside `_proc_find`. Strings referenced by the code, and the public source for this
exact kernel (`apple-oss-distributions/xnu`, tag `xnu-11417.140.69`, matching
`xnu-11417.140.69.708.3`), name the rest:

| Frame (from `__TEXT_EXEC`) | Function | Evidence |
|---|---|---|
| `0x95b5c`, `0x970e8` | `thread_block` internals | in the scheduler; called after `assert_wait` |
| `0x5c0c3c` | `proc_ref_wait` | sets `uu_wmesg = "proc_refwait"` (string found); `THREAD_UNINT` in source |
| `0x5c0910` | `proc_ref_wait_for_exec` | between `proc_find` and `proc_rele`; the only caller of `proc_ref_wait` |
| `0x5c0558` | `proc_find` | exported symbol |
| `0x5d31a0` | `proc_apply_task_networkbg` | small function in kern_resource.c: `proc_find`, then socket calls, then `proc_rele` |
| `0xba7f4` | `task_policy_update_complete_unlocked` | first action calls `task_pid` and then the function above (`tpt_update_sockets`) |
| `0x32bcc`, `0x3270c`, `0x341d0` | ipc_importance update path (`ipc_importance_task_process_updates` and callers) | `lck_spin_assert` (importance lock), then `task_update_boost_locked`, then the function above |
| `0x5adfa0` → `0x5afa68` → `0x5af814` | exec path (`proc_exec_switch_task` area → `__mac_execve` → `execve`) | kern_exec.c region; `TH_SFLAG_EXEC_PROMOTED` on the thread (`thread_set_exec_promotion` is the first line of `proc_exec_switch_task`) |
| runningboardd `0x5d3e8` → `0x60b874` | `coalition_policy_set_internal` ← `coalition_policy_set` syscall | strings `"coalition.c"`, `"unknown coalition policy: %d %d"`, entitlement `"com.apple.private.coalition-policy"` |
| ps `0x5c7d00`, sysmond/lsof `0x668c84` | `proc_iterate` (sysctl `kern.proc`), `proc_info` | each calls `proc_find` per pid |

Only the `proc_find` name and the string-backed names are certain. The rest are matched by
structure against the source. A Kernel Debug Kit for 24G517 would confirm them, but it is
no longer needed.

### Misreadings in the freeze report

| Report says | What it is | Evidence |
|---|---|---|
| "newborn process (negative pid): forked, not yet published" | The **old half of an exec**. Stackshot negates the pid of a task that "did exec" or is an "exec copy" (`kern_stackshot.c`: *"if this task is a transit task from another one, show the pid as negative"*). The same pid also appears positive, named after the new program. | -51619 bash / 51619 sed; -49605 bash / 49605 readlink; -57659 cli.test / 57659 git; -66421 alt-54debd9d / 66421 sh |
| "Process 66412 is in transition type 1": alt binary mid-exec | `transition_type 1` = `kTaskIsTerminated`: the process is **exiting** (`P_LPEXIT`). 66412 is the alt **parent** of 66421. Its last thread is in the exit path, blocked in `proc_find` on its execing child. It is a victim, not the cause. 11-07 16:20 also lists an exiting GUI app (31903) for the same reason. | `kern_stackshot.c` lines 4703-4707 |
| "every process-listing caller blocks on the same wait event … the lock holder is not visible" | There is no lock. Each waiter waits for **one pid's** exec to finish. The thread that must finish it is visible: it is the negative-pid thread, and it waits on itself. | `proc_ref_wait` source; all sharers of the wait event are callers of `proc_find` |
| "Memory was fine" | Not the cause, but not fine either. The logger at 17:51:08 on 11-13 shows 1.8 GB of swap in use, about 6.6 GB in the compressor and 1.0 M swapouts. | `~/.local/share/freeze-logger/2026-11-13.log` |
| 76 `ps` processes, "something else kept starting them" | 60 came from iTerm2's coalition (likely the Claude Code sessions, which poll `ps -A -o pid= -o ppid=`; [this public issue](https://claudeissues.com/issue/80708-bug-hung-ps-a-o-pid-o-ppid-child-processes-accumulate-until-the-per-user-process) describes such hung `ps` piling up until the per-user process limit). 14 came from a launchd job coalition at about 115 s intervals. That job is likely `claude-watchdog` (every 60 s), which is unverified. | `jetsamCoalition` of each `ps` |
| Freeze began 17:51:08 (logger stopped at `ps`) | The deadlock began at **17:51:53.66** (the stuck thread's `lastRunTime` is 1574 s before the reset). No `ps` in the stackshot blocked before the exec, so the 17:51:08 sample's `ps` either finished late (swap was heavy) or the sample stalled elsewhere. The 45 s gap is unexplained. | stackshot |
| (not in the report) | **Avast with its Endpoint Security extension** ran during the first three freezes and was gone by the fourth. Its daemons do not appear in any of the deadlock frames, and the fourth freeze had no Avast. So it is not needed for the freeze. | `procname` lists |

### Onset and order of events (from `lastRunTime`, MST)

| Freeze | Deadlock began | Stuck exec | runningboardd blocked | Reset | GUI |
|---|---|---|---|---|---|
| 11-07 a | 15:17:04.286 | bash → sed | +0.6 ms | 16:20:33 (63 min later) | WindowServer watchdog 16:18 |
| 11-07 b | 22:12:30.165 | bash → readlink | +0.8 ms | 22:13:51 | WindowServer already unresponsive from about 22:11:44 (watchdog report 22:12:24, blocked on a runningboardd thread) |
| 11-09 | 15:53:57.261 | cli.test → git | +0.3 ms | 15:54:45 | WindowServer watchdog 15:53:54 (empty report) |
| 11-13 | 17:51:53.656 | alt-54debd9d → sh | +0.6 ms | 18:18:07 | WindowServer watchdog 18:16:30, blocked on runningboardd's client work loop |

The 0.3-0.8 ms gap in every case is the strongest clue. runningboardd was already inside
`coalition_policy_set`, walking that same coalition, at the moment of the exec. The times are
real arrival times. The only thing that wakes this wait is `proc_refwake_did_exec`, so no
waiter was woken and re-blocked. A blocked thread's `lastRunTime` is therefore the moment it
blocked. No `ps` in the 11-13 stackshot blocked before the exec thread, so the logger's
17:51:08 `ps` is not in this wait.

In 11-07 b and 11-09, runningboardd (and through it WindowServer) was slow for about 40 s
before the deadlock. That fits a burst of RunningBoard state changes, but it was not traced.
On 11-13 the log shows user-activity events (HID "requestUserActive") from 17:51:50 to
17:51:53, yet the flip was into background mode. So App Nap alone does not explain that one
flip. Only a trace of runningboardd at the next freeze, or the reproducer, can say what drove it.

### Coalition and background state

| Freeze | Stuck process's coalition | iTerm2's coalition | Members | darwinBG members |
|---|---|---|---|---|
| 11-07 a | 825 | 825 | 111 | 111 |
| 11-07 b | 809 | 809 | 134 | 133 (not iTerm2) |
| 11-09 | 603 | 603 | 143 | 141 (not iTerm2, not the new `git`) |
| 11-13 | 707 | 707 | 197 | 196 (not iTerm2) |

Today, with iTerm2 in front, coalition 648 holds iTerm2, 20 fish shells, 11 `alt`, 3 tmux
servers and 3 claude processes, and none of them is at background priority 4 (`ps -o pri`). The new images
(sed, readlink, git, sh) were all flagged `boosted` (they held an importance boost), and every
stuck exec thread was `TH_SFLAG_THROTTLED`.

### Why the exact trigger is still a hypothesis

The source proves the self-deadlock path: `ipc_importance_exec_switch_task` →
`ipc_importance_inherit_from_task` → `task_update_boost_locked` →
`task_policy_update_complete_unlocked` → `proc_apply_task_networkbg` → `proc_find(own pid)`,
all between `proc_refdrain_will_exec` and `proc_refwake_did_exec`. What is not proven is
**which** change sets `tpt_update_sockets` in that window. The two candidates are a boost
transfer on its own, or a boost transfer just as RunningBoard flips the coalition's
background bit. The 4-of-4 match with runningboardd within 1 ms strongly favours the flip.
The reproducer below would settle it.

## 2. The current diagnostics

### What they can still add

- The root daemon detects the hang reliably. `ps -Ao pid=` walks every pid, so it always
  reaches the stuck one.
- **`tailspin save` will very likely hang as well.** It gathers per-process information,
  which goes through `proc_find`, and the stuck pid makes that wait for ever. Unproven, but
  the mechanism above makes it likely. If it does finish, it would show runningboardd's
  user-space stack (why RunningBoard flipped the coalition), which is the one fact still
  missing. That is now a small gain for 256 MB of wired memory.
- The user logger's `HUNG` and `RECOVERED` lines work. It does not record the background
  state, which is now the most useful thing to record.

### Changes worth making (all still unverified in a real freeze)

1. **Record the background flips.** `ps -o pri` shows 4 for a background process; this was
   checked with `taskpolicy -b sleep`. Add to each sample:
   `ps -Ao pri=,comm= | awk '$1==4' | grep -c fish` and the same count for `alt`. Note that
   `getpriority(PRIO_DARWIN_PROCESS, pid)` returned 0 for a known-background process, so do
   not use it. A 30 s sample misses short flips. A 2 s loop of `ps -o pri= -p <one fish pid>`
   costs little and catches each one.
2. **Coalition check** (no sudo), so you can verify option 2 after setup:
   ```python
   import ctypes
   lib = ctypes.CDLL('/usr/lib/libproc.dylib')
   buf = (ctypes.c_uint64 * 5)()          # struct proc_pidcoalitioninfo
   lib.proc_pidinfo(pid, 20, 0, buf, 40)  # PROC_PIDCOALITIONINFO; buf[0] = resource coalition id
   ```
3. **Post-mortem script (option 4).** Steps: read the `.diag` (JSON after line 1). Find the
   negative pid and its positive twin. Take the onset as capture time minus `lastRunTime`.
   List the threads that share its `waitEvent`, ordered by onset. Compare `jetsamCoalition`
   with iTerm2's. Then run `log show --start <onset-10s> --end <onset+5s>` for runningboardd,
   powerd and the kernel. The `.WindowServer-*.ips` files are often cut short, so parse them
   with `raw_decode` on the WindowServer process object.
4. **On detection, do something useful instead of only tracing.** Recovery is impossible:
   the stuck thread cannot be woken or killed. The daemon could `sync`, play a sound with
   `afplay` (no RunningBoard involved), and log the stuck pids. An opt-in
   `reboot -q` after a long confirmation (for example 3 minutes hung) would turn a 27-minute
   frozen screen into a clean, synced restart. It loses unsaved work, so it should be opt-in
   only. On 11-07 the machine ran for an hour after the deadlock before the screen froze, so
   an early sound alone gives time to save work.
5. **Tailspin.** Set it back to its default size, or turn it off, once option 1 or 2 is in place.

### Other capture tools

- **`ktrace` narrowed to the importance class.** `coalition_policy_set_internal` emits
  `IMPORTANCE_CODE(flavor, TASK_POLICY_COALITION)` start and end events (class
  `DBG_IMPORTANCE` = 5). A ring buffer of only class 5 plus exec events would be tiny and
  would show each flip next to each exec. The exact `ktrace` options for a filtered ring
  buffer were not checked.
- **DTrace:** SIP is on, so kernel probes (`fbt`) are not available. Not worth turning SIP off.
- **eslogger** (root plus Full Disk Access) could log every exec. The stackshot already names
  the exec, and it would add one more Endpoint Security client to the exec path. Low value.
- **spindump** walks processes as well, so it hangs too (a blocked `spindump` is in the 11-07
  and 11-13 stackshots).
- **KDK:** not needed now. If wanted, Apple's developer downloads list KDKs by build. I did not
  check whether one exists for 24G517.

## 3. Mitigations in detail

**Option 2, App Nap off for iTerm2.** RunningBoard's log shows App Nap assertions
(`com.apple.appnap` "Enable" and "AppVisible") for iTerm2. Check it like this: before the
change, hide iTerm2 or sleep the display for 2 minutes, then
`ps -Ao pri=,comm= | grep -c '^ *4 .*fish'` should be above 0. After the change it should
stay 0. If the count stays above 0 even with App Nap off, something else in RunningBoard
backgrounds the coalition, and only option 2 helps.

**Option 1, own coalition.** A coalition is inherited through fork and exec, and daemonising
does not leave it. A tmux server started from an iTerm2 shell stays in iTerm2's coalition, and
so does `svc-tmux`. launchd gives each job its own coalition. The 11-13 data shows a launchd-job coalition that stayed non-background while iTerm2's was background. That RunningBoard never backgrounds an agent with `ProcessType` `Interactive` or `Standard` is from memory, not checked. Do not use `Background`,
which would make the server permanently darwinBG. A LaunchAgent can run `tmux -L work -D` (`-D`: "Do not start the tmux server as a daemon", checked in the tmux 3.6a man page), and iTerm2 attaches with `tmux -L work attach`. Check
with the coalition snippet that `alt` and `go` are no longer in iTerm2's coalition. This also
stops tests running throttled while iTerm2 is hidden.

**Option 8, lower exec rate.** The chance per flip grows with the number of execs in flight.
`go test -p 2` and fewer parallel Altera workers lower it but do not remove it.

**Developer Tools permission: why not.** It does not touch this code path. Its cost: every
program the terminal starts skips the Gatekeeper and notarization assessment. A downloaded
tool, or something a script fetches, would run unchecked. XprotectService's high CPU
(0.4 to 3.3 hours of CPU time per boot in these stackshots) is a separate performance cost. It
did not cause these hangs.

## 4. Reproducer (design only; do not run on the host)

It freezes the machine when it works, so run it in a **macOS 15.7.4 VM** (UTM or Apple's
Virtualization framework; the VM kernel is built from the same xnu), or on the host only when
ready to hold the power button.

1. In the VM's Terminal or iTerm2, start 4 shells, each running
   `while :; do /usr/bin/true; done`. Watch `ps -Ao pri,comm` in a further shell.
2. Flip the app's coalition between normal and background mode about every 10 s. Either hide
   and show the app (`osascript -e 'tell application "System Events" to set visible of
   process "iTerm2" to false'`, then `open -a iTerm`), or `pmset displaysleepnow` followed by
   `caffeinate -u -t 2`. Confirm that `pri` moves between 31 and 4.
3. Expected: `ps` hangs within minutes, most likely on a switch *into* background mode (hide, or display sleep). That is the direction seen in the stackshots. The VM's stackshot (`sudo spindump` or a
   `forceReset` file) shows the same chain.
4. Control A: run the exec loop from a LaunchAgent (its own coalition) while flipping
   iTerm2. It should never hang.
5. Control B: run step 1 with App Nap off for iTerm2. If `pri` stays 31, it should never hang.
   This is the test for option 1.
6. To test whether a boost is needed, add a parent that receives importance-boosting XPC
   messages. This is optional.

## 5. Remaining script faults in a real freeze

- `freeze-snapshot.sh`: `tailspin save` likely blocks for ever (see above). The design limits
  the damage to one stuck process, and it logs "still running after 180s". Nothing worse.
- Both scripts start at most one stuck `ps` each. Other pollers do not: Claude Code sessions
  and the 60 s `claude-watchdog` each add a hung `ps` per poll, so the count grows. That
  is the 76 `ps` on 11-13. `claude-watchdog` could check for a stuck earlier `ps` before it
  starts another, as the logger does.
- No other faults found beyond those in `REVIEW-freeze-snapshot.md`, whose fixes are in place.

## Effort

Options 1 and 6: 5 minutes. Option 3: 20 minutes. Option 4: 1 hour. Option 2: 1-2 hours,
and it ends running tmux sessions. Option 5: 30 minutes. Option 7: half a day.
