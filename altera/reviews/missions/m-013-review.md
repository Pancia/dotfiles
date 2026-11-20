Summary: Reviewed f5274f4f (worker/w-19) against alt/review/g-001 4b942f05. The change meets R1.1-R1.3 and every success criterion: the here test now uses the unchanged `in_pane` fixture, the new tmux-keyed test sets its own `ITERM_SESSION_ID`, `TMUX` and `TMUX_PANE`, and the worklog records the confirm-first runs (1 failed with a fake TMUX, 61 passed without).

No BLOCKING or MINOR findings. Notes:
- Scope: only `tests/lib/python/test_revive.py` and the new worklog changed; no live path, doc or `lib/python/revive.py` change.
- `tests/lib/python/test_revive.py:413` (`test_here_under_tmux_finds_the_tmux_pane_ghost`) also writes a bare `<G>-100.rec` ghost and asserts the tmux ghost's cwd and command, so it fails if the tmux suffix in `this_pane_key()` (`lib/python/revive.py:239`) is dropped, not only when nothing matches.
- Hermetic: both tests write under `tmp_path` through the `store` fixture, which also stubs `iterm_tree`; the fake `TMUX` value is only an environment string and no tmux server is contacted.
- The done check is real: it sets a fake outer `TMUX`/`TMUX_PANE`, under which the old test failed on the base commit, and it requires both test names as PASSED. The stored self-check passed at f5274f4f.
- `refs/alt/tasks/m-013` equals the tip, so no work is lost. No targeted test run was needed.
