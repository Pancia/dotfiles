# Mac mini freezes, Nov 2026

> Current summary: [docs/mac-freezes.md](../../docs/mac-freezes.md). This file is the
> first analysis, kept as a record; its "Diagnostics in place" sections are out of date.

Four freezes ended with a power-button reset (`panic: btn_rst`):
2026-11-07 16:20, 2026-11-07 22:13, 2026-11-09 15:54, 2026-11-13 18:18 (MST).
Reports: `/Library/Logs/DiagnosticReports/forceReset-full-*.diag` (JSON after line 1).

> **Correction, 2026-11-14.** Parts below are wrong. See
> [REVIEW-freeze-options.md](REVIEW-freeze-options.md), checked against the
> stackshots: the negative pid is the *old half of an exec*, not a newborn (each
> pairs with the same positive pid under a new name: bash->sed, bash->readlink,
> cli.test->git, alt->sh). The process deadlocks on itself mid-exec, and every
> caller that touches that pid (ps, lsof, iTerm2, runningboardd) waits on it.
> "Transition type 1" is an exiting parent, a victim. syspolicyd, XprotectService
> and amfid were idle at all four freezes, so the XProtect guess is out. Likely
> trigger: RunningBoard switching iTerm2's whole coalition into background mode
> during the exec. Altera raises the exec rate inside that coalition; it is not
> the cause.

## Same signature every time

- One newborn process (negative pid in the stackshot: forked, not yet published)
  is blocked uninterruptibly in the kernel.
- Every tool that walks the process list (`ps`, `lsof`, `sysmond`, `watchdogd`,
  `runningboardd`, iTerm2) blocks on the **same wait event** as that child.
- Kernel stacks are identical across all four reports. Shared prefix
  `T+0x970e8 < T+0x95b5c < T+0x5c0c3c < T+0x5c0910 < T+0x5c0558`; the child then
  goes `< T+0x5d31a0 < ... < T+0x5adfa0`, `ps` goes `< T+0x5c7d00 < ...`.
  Unsymbolicated (kernel 24.6.0, xnu-11417.140.69.708.3).
- The lock holder is not visible. Memory was fine (no pressure flag, 38-42% free).

| Freeze | Stuck child | Altera processes live |
|---|---|---|
| 11-07 16:20 | bash | alt-7b414cb, alt-05d4740 |
| 11-07 22:13 | bash | alt-*, git.test, e2e.test, daemon.test |
| 11-09 15:54 | cli.test | alt-*, cli.test, daemon.test, e2e.test, link |
| 11-13 18:18 | alt-54debd9d | alt-*, 17 appshoot/appenv.test (worktrees w-748, w-750), cli/daemon/promote.test |

Altera was running at all four; a Go test burst was running at three. Altera is the
likely trigger (heavy parallel fork/exec), not proven. The hang itself is in macOS.

## 11-13 timeline (freeze-logger)

- 17:45-17:51 load rose 8 -> 14; two `claude` at 100% CPU; `go=0` at 17:50:37.
- 17:51:08 sample stopped at the `ps` step: the freeze began here.
- 18:18 power reset; 76 `ps` processes piled up. Not the logger's: it stopped at its first one. Something else kept starting them.

## Diagnostics in place

- `services/freeze-logger` (uncommitted as of 11-13): 30 s samples in
  `~/.local/share/freeze-logger/`. It calls `ps`, so it hangs with the machine.
- `bin/shadow-hang-trace`, `bin/shadow-pcap`: for Shadow input lag, unrelated.

## Added 2026-11-13 evening

- The shipped kernel (`/System/Library/Kernels/kernel.release.t8103`, UUID matches)
  is stripped, so the frames cannot be named. Naming the lock needs Apple's Kernel
  Debug Kit for build 24G517.
- `freeze-logger` now gives `ps` 10 s. On a hang it writes `HUNG:` lines and starts
  no new `ps`, instead of dying silently. It also counts `alt` processes.
- `services/freeze-logger/root/`: a root LaunchDaemon (`freeze-snapshot`). Every
  20 s it lists processes; if that takes over 10 s it runs
  `tailspin save -n -l 300` into `/Library/Logs/freeze-snapshot/`. tailspin keeps
  a rolling kernel trace, so the file should show who took the lock first.
  Install: `sudo services/freeze-logger/root/install.sh` (also runs
  `tailspin enable`). Unproven on a real freeze: `tailspin save` may itself hang.
- macOS 15.8.3 is available (running 15.7.4).

## Trace history, 2026-11-14

- 256 MB buffer, 10 ms full-system sampling, quiet machine: 8.3 s of history.
- 256 MB, 100 ms sampling, during an Altera Go test run (load 36): 4.6 s.
  Events then: 35% C0x07/S0x01, 28% C0x03/S0x01 (file system), 19% C0x1f/S0x05
  (dyld image loads, i.e. new programs starting). Sampling is no longer the cost.
- Same moment: XprotectService at 94% CPU and fseventsd at 60%, with e2e.test and
  cli.test running. Guess, unchecked: each freshly built test binary gets a
  malware scan when it starts, and the stuck child in the freezes was always a
  process starting a program (11-13: "Process 66412 is in transition").

## Change, 2026-11-14

- The root watcher no longer saves tailspin traces. On a hang it runs `sync` and
  plays a sound 3 times. The installer resets tailspin and turns it off again,
  freeing the 256 MB. Reason: REVIEW-freeze-options.md.
