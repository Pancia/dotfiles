Summary: Reviewed 4b942f05 (worker/w-16) against alt/review/g-001 31c30416. The change meets R2.1, R2.2 and every success criterion with one test file and a worklog; no blocking or minor finding.

- Checked, no finding: `no_tmux_env()` (tests/svc/test_svc.py:189) drops only `TMUX` and `TMUX_PANE`, and `Pane.__init__` passes `env=` to `execvpe` (tests/svc/test_svc.py:125-129), so no fixture change is needed.
- Checked, no finding: all four pane tests other than the q-under-tmux test now pass the helper (tests/svc/test_svc.py:215, :247, :269, :286). This covers the brief critique's point about the tty-mode and closing-the-terminal tests.
- Checked, no finding: `test_q_under_tmux_stops_but_keeps_the_supervisor` keeps its own fake `TMUX` (tests/svc/test_svc.py:232-233).
- Checked, no finding: the worklog records the confirm-first runs with `TMUX` set (2 failed, 3 passed) and unset (5 passed), as R2.2 asks.
- Checked, no finding: the stored done check sets `TMUX` and `TMUX_PANE` and asserts the three tests pass, so it fails without the change and tests it directly.
- Checklist: no live path, no private data, tests stay hermetic, no `rm`, no fish file, no doc change needed for a test-only fix. The task ref is an ancestor of the tip; nothing outside the mission is deleted or rewritten.
- No test run: reading settled every question.
