# Mission: Runner gives each component a throwaway home and identity, and pins uv

**Date**: 20261119-142514-MST
**Task**: m-016 bold-leaf

## Objective
Implement row ISOLATE (requirement R4) of the spec `altera/specs/20261119-121426-MST-green-hermetic-test-suite-for-the-merge-gate.md`. The spec's requirements, its binding decisions and its global rules G1 to G4 are authoritative; read it with `git show master:<path>`. Altera inserts the row's done-check block.

## Done Check

```donecheck
{"v":1,"timeout":"5m","checks":[
 {"kind":"command","title":"isolation unit tests","run":"uv run lib/python/run_tests.py lib/python/test_run_tests.py -v","stdout_contains":["test_isolated_env_points_home_and_xdg_into_the_test_home PASSED","test_isolated_env_keeps_the_uv_folders PASSED","test_isolated_env_drops_terminal_and_claude_variables PASSED","test_isolated_env_puts_the_tree_bin_first_on_path PASSED","test_test_home_links_dotfiles_to_the_tree_under_test PASSED","test_run_pytest_runs_under_the_isolated_env PASSED"]}
]}
```

## Context
- The binding decision is that isolation lives in the runner, not in a conftest fixture. That covers every component, including `roleplay` through the `tests/roleplay` symlink, and paths a test module computes at import time.
- `lib/python/run_tests.py` on master:
  - `DOTFILES` (line 15) and `COMPONENTS` (line 23);
  - `stream()` (line 185) takes no env today;
  - `run_pytest()` (line 199) is reached from `run_component`, `run_unit_group` and `main`'s single-file path. Make isolation apply on every path.
- R4.1: add a pure `isolated_env(base, home, uv_cache, uv_python) -> dict` and a context manager `test_home()`. `test_home()` makes a `tempfile.TemporaryDirectory(prefix='dotfiles-test-home-')` holding:
  - a `dotfiles` symlink to `DOTFILES`;
  - `.config/`, `.local/share/`, `.local/state/` and `.cache/`;
  - a `.gitconfig` with a test identity and `init.defaultBranch = master`;
  - `.config/jj/config.toml` with a `[user]` table.
- R4.2: the variables `isolated_env` sets:
  - `HOME`, and the four XDG folders at their standard paths under `HOME`. `lib/python/ccjj.py` hard-codes `~/.local/state/ai-jj-commit` (lines 283, 702 and 2888);
  - `GIT_CONFIG_GLOBAL`, `GIT_CONFIG_NOSYSTEM=1`, `JJ_CONFIG`, `JJ_USER` and `JJ_EMAIL`;
  - `UV_CACHE_DIR` and `UV_PYTHON_INSTALL_DIR`;
  - `PATH`, with the tree's `bin` first and every other `dotfiles/bin` copy removed. `tests/fish/test_trash.py` (lines 22 to 29) and `tests/fish/test_cc_worktree_wrapper.py` (lines 11 to 15) guard against this by hand today.
- R4.2: the variables `isolated_env` removes: `TMUX`, `TMUX_PANE`, `ITERM_SESSION_ID`, `TERM_SESSION_ID`, `CLAUDECODE`, `SVC_FS_CONFIG`, `SVC_TMUX_SOCKET`, and every name that starts with `CLAUDE_`, `CCS_` or `CC_JJ_`. It keeps every other variable.
- R4.3: compute the uv folders once from the real environment. Use existing `UV_CACHE_DIR` and `UV_PYTHON_INSTALL_DIR` first, else `uv cache dir` and `uv python dir`. Run each pytest under `test_home()` with `isolated_env`, and give `stream()` an `env` parameter.
- R4.4: a `COMPONENTS` entry may hold `isolation: False` and an `isolation_reason` string. The runner then inherits the environment and prints the reason. No component uses it in this row; REST-A and REST-B may.
- The symlink exists because scripts hard-code `$HOME/dotfiles`, for example `MANIFEST=` at line 12 of `rcs/claude-ensure-rcs-hook.sh`.
- `GIT_CONFIG_GLOBAL` also replaces the live `hooksPath` set at line 6 of `rcs/gitconfig`.
- R4.5: add the six named tests to the existing `tests/lib/python/test_run_tests.py`. In `test_run_pytest_runs_under_the_isolated_env`, monkeypatch `stream` so that no real pytest runs.
- R4.6, docs:
  - `docs/testing.md` has only its title heading on master. Add a new Isolation section: what is set, what is removed, the `PATH` rule, why uv is pinned, the opt-out key, and that `cmds test` gets the same isolation;
  - add one paragraph to the `### Testing` section of `CLAUDE.md` (line 352);
  - both must contain the exact phrase: after this row merges, `hooks`, `astro` and `roleplay` fail under `cmds test` until HOOKS, ASTRO and REST-A land. CANARY searches for the phrase `until HOOKS, ASTRO and REST-A land` and removes it.
- Residual risk: under a fake `HOME`, uv loses `~/.config/uv/uv.toml`. If the suite needs it, pass `UV_CONFIG_FILE`. Record what you found in the worklog.
- REVIVE, SVC-KEYS and SVC-EXIT have merged. Their tests set their own environment, so they must still pass once the runner strips `TMUX`.

## Constraints
- You work in a git worktree. Use `git`; `jj`, `g`, `commit-mine` and `ccjj` are denied. Never push.
- Run tests with `uv run lib/python/run_tests.py <component or file>` from the worktree root, never `cmds test` (it tests ~/dotfiles, not your tree).
- Tests are hermetic: no test touches the real HOME, ~/.config, ~/Library/LaunchAgents, ~/.claude, a live tmux server or a running service.
- Never use `rm`; use `trash`. Never write a secret or private detail into a tracked file: the repository is public.
- This is not a live path: `lib/python/run_tests.py` runs only under `cmds test` and the gate. In the mission-ready note, tell the operator that `hooks`, `astro` and `roleplay` stay red under `cmds test` until HOOKS, ASTRO and REST-A land.

## Success Criteria
- The six tests from R4.5 pass, and the existing tests in `test_run_tests.py` still pass.
- `lib/python/test_revive.py` and the svc pane and clean-exit tests still pass under the new runner.
- `docs/testing.md` has the Isolation section. The `CLAUDE.md` Testing section has the new paragraph. Both carry the interim-red phrase.
- Every check in the done check passes.

## Out of Scope
- Fixing individual components under isolation (ASTRO, HOOKS, CCJJ, FISH, REST-A, REST-B).
- Setting any opt-out (REST-A, REST-B).
- Per-component timing (TIMING) and the guard tests (CANARY).
- Shared files and their owners in order: `lib/python/run_tests.py` goes ISOLATE, REST-A, REST-B, TIMING; `docs/testing.md` goes ISOLATE, REST-A, REST-B, TIMING, CANARY; `CLAUDE.md` goes ISOLATE, then CANARY.
