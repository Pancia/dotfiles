Class: product bug

# Report: the clean-exit svc test (row SVC-EXIT)

Mission m-015, spec `green-hermetic-test-suite-for-the-merge-gate`, requirement R3.

## Summary

`test_clean_exit_closes_the_window_crash_keeps_it` fails now and then, about one run
in seven. `TMUX` makes no difference. The failing assertion is always the last one,
the crash-screen check (`assert "broken crashed (exit 3)" in screen and "boom-message"
in screen`; line 780 in the brief's numbering, line 812 on the base commit). The
earlier assertions always passed. The clean stop always closed the web window, and
the broken window was always dead.

Two separate causes give that one failure:

1. **Product bug, in `bin/supervise`.** The `tee` that copies the child's output to
   the pane and to `.run/<name>.log` is a process substitution. Under bash 4+ (this
   machine runs bash 5.3 through `#!/usr/bin/env bash`), the shell starts it inside
   the child's process group. A `ps` with a test script showed this. Under the
   system bash 3.2 it sits in the supervisor's group. `drain_group` sends TERM to the
   whole group after the child exits, so it also kills a `tee` that has not yet
   read the pipe. When the service crashes at once, its error is then lost from
   **both** the pane and the log. That is the error the crash window exists to show.
   The same TERM also cut off a service's shutdown output on every `svc stop` and
   restart.
2. **Test bug.** When a pane dies under `remain-on-exit`, tmux draws the
   `remain-on-exit-format` line by moving to the bottom row and sending a line feed.
   This scrolls the pane up by one line, so its first line goes into history. The
   output lines arrive in a random order, because `tee` runs asynchronously from the
   supervisor's own `say` lines. When `boom-message` was the first line, it went into
   history. The test read only the visible screen (`capture-pane -p`), so it failed.
   A person still sees the error by scrolling up one line, so this is not a product
   defect.

The class is **product bug**, because cause 1 loses real output for the operator.
Cause 2 is fixed in the test as well.

## R3.1 Reproduction: fifteen runs on the base commit

Command: `uv run lib/python/run_tests.py svc/test_svc.py -v -k clean_exit_closes`,
from the worktree root, with the test and `bin/supervise` unchanged.

| Setup | Run 1 | Run 2 | Run 3 | Run 4 | Run 5 | Failed |
|---|---|---|---|---|---|---|
| `TMUX` set (the command runs inside an outer tmux pane) | pass | pass | **fail** | pass | pass | 1/5 |
| `TMUX` unset (`env -u TMUX -u TMUX_PANE`) | pass | pass | pass | pass | pass | 0/5 |
| Inside a pane of a private tmux server (`tmux -L svcrepro-<id> new-session -d …`) | pass | **fail** | pass | pass | pass | 1/5 |

Both failures were at the crash-screen assertion, and the visible screen started with
`[supervise] broken exited (rc=3); supervisor stopping.`. `boom-message` was missing,
and so was the `pid=` line, which had scrolled into history. That is the pattern of
cause 1: `boom-message` was never written. Each test starts its own tmux server, with
`TMUX` removed by the `tmux_env` fixture, so the outer `TMUX` cannot reach the
service. The clean run with `TMUX` unset is chance: the failure rate is low.

**Original failure.** The operator saw it in a full suite run started from inside
their own interactive tmux session, so `TMUX` was set in the environment. The table
shows that this setting does not matter. That run failed in the same intermittent
way.

### Instrumented runs (diagnosis, not part of the fifteen)

The failure message was extended to print the pane size, the full history
(`capture-pane -p -S -`) and `.run/broken.log`. Then 16 more runs were made:

- 1 failure with an **empty log** and no `boom-message` in the history. The output
  was lost: cause 1.
- 2 failures with `boom-message` **in the log and in the history**, as line 1, while
  the visible screen started at the `pid=` line. It had scrolled out: cause 2.
- 13 passes.

The pane was 50x200, so a shortage of rows could not explain the scroll. Each failure
had exactly one line of history, which matches tmux's one line feed.

A temporary trace in `drain_group` listed the group's members before the TERM. For a
long-running service (`web`), `tee -a .run/web.log` is in the child's group, so it
receives that TERM.

### The race, in isolation

A loop of 200 runs of `cmd > >(tee -a log) 2>&1 &`, then `wait`, then
`kill -TERM -$child`, with `cmd` = `echo boom; exit 3`, under bash 5.3:

- idle machine: 0/200 lost;
- 12 busy processes on 8 cores: **2/200 lost**;
- the same load with `>(trap '' TERM; exec tee …)`: 0/400 lost.

## R3.2 Reading `bin/svc-tmux`

- The `new-window` launch (first window `new-session`, with `-x 200 -y 50`) starts
  `supervise <name>` directly as the pane command. It does not wrap it or redirect
  output, so svc-tmux adds nothing to the race.
- `--wait` (`timeout=180` by default; the test passes 10 for `broken`) returns as soon
  as `wait_ready` sees the window dead and no live supervisor. By then `supervise`
  has exited, and before exiting it has drained its group, so any loss has already
  happened.
- A dead pane is respawned only by a later `up` (`respawn-pane`, never `-k`). The test
  never respawns, so the respawn path is not involved.
- `svc stop` (`cmd_stop`) sends TERM to the pid in the pidfile. It does not use tmux,
  so the missing `tmux_env` on that call did no harm in this test. It is still a
  defect, and it is fixed below.

## R3.3 Fix

**Product, `bin/supervise`** (a live path; see below). The tee is now
`>(trap '' TERM; exec tee -a "$logfile")`. An ignored signal stays ignored across
`exec`, so `tee` outlives the TERM and stops at EOF, when the last writer closes the
pipe. `drain_group` already waits until the group is empty, so the supervisor exits
only after the output is written. Trade-off: if a process leaves the group but keeps
stdout open, `tee` stays open until the drain sends KILL after about 10 seconds.
Before, TERM ended it at once. `wiki/pages/supervise-svc.md` documents this
("Output is never cut off").

**Tests, `tests/svc/test_svc.py`:**

- `svc stop web` now gets `tmux_env`.
- The test now waits for the `broken 1` dead-window entry with `wait_for` instead of
  reading the listing once.
- The crash screen is captured with `-S -` (history included), and the test waits for
  both strings. It also checks that `boom-message` is in `.run/broken.log`. The wiki
  page records the tmux line-feed behaviour that makes `-S -` necessary.
- New `test_stop_keeps_the_service_shutdown_output`: a service with a TERM trap
  prints `shutdown-message` when it is stopped. This deterministic test failed 5 of 5
  times with the old `supervise`, because the log held only `graceful-up`, and it
  passed 5 of 5 times after the fix.

**After the fix:** the clean-exit test passed 20/20 on an idle machine and 10/10
under the same CPU load. The whole `svc` component passed, 36 tests in 72s.

## Live-path check for the operator

`bin/supervise` runs from `~/dotfiles/bin` once this merges. In a project that has a
`.svc.conf`, run `svc-tmux up --wait <name>`, then `svc stop <name>`. The window
must close. A service that crashes at startup should now always show its error in
the dead pane (scroll up one line if needed) and in `svc logs <name>`.
Supervisors that are already running keep the old code until they are restarted.
