# Mac mini freezes (Nov 2026)

Five hard freezes between 2026-11-07 and 2026-11-14, each ended by holding the
power button. The screen froze, nothing responded, and the panic report reads
`panic: btn_rst` (a power-button reset, not a crash).

## Cause

A macOS kernel bug, as far as the evidence goes.

- A process in the middle of `exec` (bash starting `sed`, `cli.test` starting
  `git`, and so on) deadlocks on itself. Inside the exec it updates its own
  task policy, which calls `proc_find` on its own pid, which waits for the exec
  to finish. Only that thread can finish it.
- Everything that then touches that pid waits for ever: `ps`, `lsof`, iTerm2,
  and `runningboardd`. runningboardd holds a global lock while it waits, so
  WindowServer stops too, and the screen freezes.
- This happens only when RunningBoard changes the background flag of the
  process's whole app group (its *coalition*) at that same instant, into or out
  of background mode. A coalition that is already in background mode is safe.

The call chain was matched by hand to Apple's public xnu source for this kernel
(tag `xnu-11417.140.69`). The shipped kernel has no symbols, and no Kernel Debug
Kit was used.

## Trigger

**Game Mode, turned on by Shadow PC.** Shadow's display app declares the games
category, so in full screen macOS turns Game Mode on. RunningBoard then moves
about 50 apps, iTerm2 included, to background mode in one sweep. Every freeze
began with Shadow in front. iTerm2 went to background mode only on days Shadow
was used.

Everything run from iTerm2 is in iTerm2's coalition: tmux, Claude Code
sessions, Altera and its `go test` runs. The more programs start there, the
more likely one is mid-exec during a sweep. Altera's test runs raise the odds;
they are not the cause. Risk was about 3% per Game Mode sweep.

Ruled out: memory pressure (none), the malware scanner (idle at every freeze),
App Nap (no background switches on heavy non-Shadow days).

## Fix in place

- **Game Mode is off for Shadow** (2026-11-15): with Shadow in full screen,
  menu bar → game controller icon → "Turn Game Mode Off". macOS keeps it off for
  that app. Running Shadow in a window also avoids Game Mode.
- macOS 15.8.3 since 2026-11-14. Unknown whether it fixes the kernel bug.

If freezes return with Game Mode off, the next step is to run tmux and Altera
from launchd agents, outside iTerm2's coalition. That is costly: `revive` and
`ccs` key on `ITERM_SESSION_ID`, and Altera starts its own tmux servers from
iTerm2 tabs.

## Checking a new freeze

1. **Copy the report at once.** macOS deletes old
   `/Library/Logs/DiagnosticReports/forceReset-full-*.diag` files within days.
   Keep copies in `.cc/private/freeze-evidence/stackshots/` (not in git).
2. **Read it.** The file is one JSON header line, then a JSON body
   (`processByPid`). The signature of this bug:
   - one process with a **negative pid**: the old half of an exec. The same
     positive pid exists under the new program's name.
   - its single thread is `TH_WAIT, TH_UNINT`, and `ps`, `lsof`, iTerm2 and
     `runningboardd` threads wait on the **same `waitEvent`**.
   - "Process N is in transition type 1" in `notes` is an exiting parent, a
     victim.
3. **Game Mode log.** `log show --last 1d --predicate 'process == "gamepolicyd"
   AND eventMessage CONTAINS "Game mode"'` lists each on/off switch. macOS keeps
   these lines for about a day.
4. The report's timestamp is written after the restart. The real start of the
   freeze is 40–70 s earlier.

## Diagnostics (all off)

Kept in the repo, none running:

| Tool | What | Turn on |
|---|---|---|
| `services/freeze-logger/` | 30 s samples of load, memory, top processes; marks a hung `ps` | rename `org.pancia.freeze-logger.plist.disabled` back to `.plist` |
| `services/freeze-logger/root/` | root daemon: on a hung `ps`, flush disks and play a sound | `sudo services/freeze-logger/root/install.sh` (`--uninstall` removes it) |
| `bin/shadow-hang-trace`, `bin/shadow-pcap` | Shadow input-lag tools; unrelated to the freezes | run by hand |

tailspin is off (macOS default). An earlier version used it with a 256 MB
buffer: that held only 4–8 s of history and would likely hang on save.

## Records

- `.cc/reports/REPORT-mac-freezes-2026-11.md` — the first analysis; read its
  correction block first.
- `.cc/reports/REVIEW-freeze-options.md` — the kernel call chain.
- `.cc/reports/REVIEW-freeze-snapshot.md` — code review of the diagnostics.
- `.cc/plans/PLAN-mac-freeze-investigation.md` — the investigation plan.
- `.cc/private/freeze-evidence/` (not in git, no backup) — the review that found
  the Game Mode trigger (it holds app-usage times), log extracts, stackshots.
