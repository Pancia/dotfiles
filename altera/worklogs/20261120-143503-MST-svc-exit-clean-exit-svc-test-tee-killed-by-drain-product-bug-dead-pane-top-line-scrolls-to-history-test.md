# Worklog: SVC-EXIT: clean-exit svc test - tee killed by drain (product bug) + dead-pane top line scrolls to history (test)

**Date**: 20261120-143503-MST
**Task**: m-015
**Agent**: w-22

## Summary

Diagnosed `test_clean_exit_closes_the_window_crash_keeps_it`. The test failed now and then (2/15 in the R3.1 runs: TMUX set 1/5, unset 0/5, private tmux pane 1/5), always at the crash-screen assertion. TMUX makes no difference. There were two causes. (1) Product bug: under bash 4+, `supervise`'s `>(tee -a log)` is in the child's process group. `drain_group`'s group TERM killed it before it had read the pipe, so a fast crash's error was lost from both the pane and the log. The same TERM cut off shutdown output on stop and restart. Fixed with `>(trap '' TERM; exec tee ...)`. (2) Test bug: tmux's remain-on-exit line feed scrolls the dead pane's first line into history, and the test read only the visible screen. Fixed with `capture-pane -S -` and bounded waits. The stop call now passes `tmux_env`. Added the deterministic `test_stop_keeps_the_service_shutdown_output`: 5/5 failures before the fix, 5/5 passes after. After the fix, the clean-exit test passed 20/20 idle and 10/10 under CPU load, and the full svc suite passed (36). Updated the wiki. Report: `.cc/reports/REPORT-svc-clean-exit.md`.

## How It Went

The failure reproduced on the first five runs, which made it quick. Printing the history and `.run/broken.log` in the assertion message separated the two causes at once. An empty log means the output was lost. A full log with the line in history means it scrolled out. A one-off trace in `drain_group` showed tee in the child's group. A 200-iteration race script reproduced the loss only under CPU load (2/200), and the fix brought it to 0/400.

## System Learnings

- With bash 5 and `set -m`, a process substitution on a background job's redirection sits in that job's process group (its parent is the job). Under bash 3.2 it sits in the parent shell's group. So `kill -- -$pgid` also kills the tee.
- tmux 3.6: when a pane dies under `remain-on-exit`, tmux moves to the bottom row and sends a line feed to draw `remain-on-exit-format`, so one line always scrolls into history. Read dead panes with `capture-pane -p -S -`.

## Process Improvements

- A flaky assertion that reads tmux output should print the history and the relevant log file in its message. That doubles the information each failure gives.

## Self-Improvement Notes

- I ran the reproduction directly instead of through subagents. Each step was one short command, and the output was the evidence for the report.
