# PLAN: `revive` reopens the pane's nvim session

Goal: after a power cut, `revive` in a pane that had nvim open offers to reopen
the same files, splits, tabs and cursor positions, however nvim was started.

Tags: **[measured]** a number from an experiment, **[verified]** behavior seen
in an experiment, **[inferred]** follows from something measured but not
observed directly, **[unverified]** not tested. Experiments ran on
2026-11-14 with nvim 0.11.5 and fish 4.1.2. The scratch prototype
(`/private/tmp/claude-501/nvsess/proto/`: `revive_session.lua`,
patched `journal.fish`, pty driver `drive.py`, scenarios `s1.py`–`s3.py`)
will be lost at reboot. The parts that matter are copied below.

---

## 1. Plan

### 1.1 Shape

- Each nvim started through the `nvim` fish wrapper, from a journaling shell,
  writes `mksession` output to its own file in a per-pane folder.
- A clean nvim exit deletes its file. Only a hard death (power cut or SIGKILL)
  leaves one behind.
- When the next shell adopts the pane record into `ghosts/`, it moves the
  folder with it, under the same name.
- Picking up the ghost offers `nvim -S <file>`.

### 1.2 Store layout (adds to docs/revive.md "The store")

```
live/<key>.nvim/<nvim-pid>.vim         session of each nvim this shell started
live/<key>.nvim/<nvim-pid>.vim.tmp     write in progress (never read)
ghosts/<key>-<epoch>.nvim/             moved here with ghosts/<key>-<epoch>.rec
reopen/<key>-<epoch>.vim               a session being reopened by `revive`
```

`<key>` is `_revive_pane_key` (GUID, plus `-<tmux pane>` inside tmux). Each
nvim writes its own file, named by its pid, so two nvims in one pane never
write the same file. That happens when one is stopped with Ctrl-Z and a second
one starts.

### 1.3 How nvim learns its pane: a variable set only by the wrapper

`fish/functions/nvim.fish` (the wrapper with the restart loop) is what `v`,
`vim`, `vims` and a plain `nvim` all reach. `v` calls `nvim`, `vim` calls
`nvim`, and `vims` calls `vim`. This is from reading the source; only a plain
call of the wrapper was run. The wrapper sets the folder for its own child
only:

```fish
set -l dir
test -n "$__revive_rec"; and set dir (string replace -r '\.rec$' .nvim -- $__revive_rec)
REVIVE_NVIM_DIR=$dir command nvim $argv        # and the same in the restart loop
```

- The variable is never exported from the shell. A `git commit`, `jj describe`
  or `cmds` started at the prompt cannot see it. **[verified]**: with
  `GIT_EDITOR=nvim`, no session was written.
- `$__revive_rec` is empty in a nested or non-interactive fish, so an nvim
  started there gets an empty value and does nothing. **[verified]**: a nested
  fish in `:terminal`, then nvim, wrote nothing.
- **The owning nvim unsets the variable in its own environment at startup**
  (`vim.env.REVIVE_NVIM_DIR = nil`). After that, no child inherits it, whether
  from `:!`, `system()`, `jobstart` or `:terminal`. **[verified]**: all three
  saw an empty value. So `:!git commit` from inside nvim, which opens a second
  nvim as git's editor, cannot claim the pane either.

An alternative was tested and rejected: export the folder and the shell pid
globally, and let nvim check its parent pid.
- In nvim 0.11 the Lua code runs in the `nvim --embed` server, whose parent is
  the TUI `nvim`, not the shell. **[verified]**: server ppid was the TUI pid,
  and the TUI ppid was fish.
- The check therefore needs the grandparent. `nvim_get_proc` forks `ps` for
  that, at **10 ms per start [measured]**.
- The check depends on the TUI/server split, which may change.
- `sh -c "nvim f"` passes the check by accident, because sh execs its last
  command. **[verified]**
- Its only gain is `command nvim`, `exec nvim` and `xargs nvim`. See Q2.

### 1.4 nvim side: `nvim/lua/revive_session.lua`, new

Called from `nvim/init.lua` as `pcall(function() require('revive_session').setup() end)`,
right after `package.path` is set and before the plugin `require`s. A plugin
error must not stop it. It is skipped under `vim.g.vscode`. The module was
prototyped and the pty runs below pass with it. In outline:

```lua
local OPTS = 'buffers,curdir,folds,tabpages,winsize'   -- no blank/help/terminal/options
setup():
  d = vim.env.REVIVE_NVIM_DIR; vim.env.REVIVE_NVIM_DIR = nil
  if d empty -> return
  mkdir -p d; path = d..'/'..getpid()..'.vim'; tmp = path..'.tmp'
  augroup: VimEnter BufEnter WinNew WinClosed TabNew TabClosed BufDelete
           DirChanged VimResized VimResume FocusLost SessionLoadPost -> later(300)
           CursorHold -> later(2000)
           VimLeavePre -> leaving = true; stop timer; remove path and tmp
                          (an in-flight rename callback sees `leaving` and deletes instead)
save():
  skip if vim.g.SessionLoad, v:exiting set, or a write is in flight (mark "again")
  save &sessionoptions and v:this_session; set OPTS
  unlist buffers with buftype ~= '' (plugin buffers), remember them
  silent! noautocmd mksession! tmp
  restore buflisted, &sessionoptions, v:this_session
  read tmp; if identical to the last body written -> stop (no flush)
  async: fs_open(tmp) -> fs_fsync -> fs_close -> fs_rename(tmp, path)
  on completion: last = body; if "again" -> schedule save()
```

- `later(ms)` is a trailing-edge debounce on one libuv timer.
- `CursorHold` fires once per pause, 200 ms after the last key, because
  `updatetime=200` in `autogroups.vim`. A 2 s debounce on top keeps cursor-only
  saves to at most one per pause.
- Layout events save after 300 ms.

### 1.5 Durability against a power cut

- docs/revive.md rejects tmp + rename because **fish** cannot `fsync`, so APFS
  may commit the rename before the data. nvim can flush the data first.
- `vim.uv.fs_fsync` is libuv's fsync. On macOS, libuv issues `F_FULLFSYNC`.
- **[measured]**: `fs_fsync` takes 4.7 ms per call, `F_FULLFSYNC` from Python
  4.4 ms, plain `fsync` 0.03 ms. That libuv uses `F_FULLFSYNC` is
  **[inferred]** from the matching times and libuv's source. It was not traced.
- The flush runs on the libuv thread pool, so the UI does not wait.
- Order: data is durable, then the rename. A power cut before the rename keeps
  the previous file, which was flushed on its own save. It can never leave a
  zero-length session. Only the very first save can be lost, which leaves no
  session.
- The reader also requires the last line to be `" vim: set ft=vim :`, which
  `mksession` always writes **[verified]** in every session produced. A torn
  or foreign file is ignored.
- The files themselves: `noswapfile` is set (`settings.vim`). The existing
  `AutoSave` does `silent! wa` on CursorHold, InsertLeave and TextChanged with
  `fsync` on. `writefile(…,'s')` costs 4.3 ms **[measured]**, the same as a
  full flush, so nvim's own writes reach the disk. That last point is
  **[inferred]**. This plan does not change it.

### 1.6 Journal changes: `fish/functions/revive-journal.fish`

1. **Adoption.** Next to `mv -f $rec $ghost`:
   `test -d $root/live/$key.nvim; and mv -f $root/live/$key.nvim (string replace -r '\.rec$' .nvim -- $ghost)`.
   This forks only when a folder exists, and only on the orphan path.
   **[verified]** in pty: the folder arrived as `ghosts/<key>-<epoch>.nvim/<pid>.vim`
   with the trailer, and with all three files of a vsplit and a tab.
2. **`fish_exit`.** Add the folder to the existing `rm`:
   `command rm -rf $__revive_rec (string replace -r '\.rec$' .nvim -- $__revive_rec)`.
   The path comes from `$__revive_rec`, never from an environment variable.
   It is still one fork.
3. **Stale files.** A crashed nvim (segfault, OOM kill) under a live shell
   leaves its file behind. A later power cut would then offer an nvim that
   was not open.
   - In `_revive_on_postexec`, when `jobs -q` is false (no running or stopped
     job), glob `$nvdir/*.vim`. Both are builtins. Any match must be stale,
     because every wrapper-started nvim is a job of this shell. Remove the
     matches with one `command rm`.
   - **[measured]**: the check costs about 0.03 ms when nothing matches. It
     forks only when stale files exist.
   - A stopped nvim keeps `jobs -q` true, so its session survives.
4. **Banner.** `_revive_render_banner` reads the sibling `.nvim` folder.
   It picks the newest file with the `path mtime` builtin **[verified]** on
   fish 4.1.2, takes the `badd` names with `string match`, and prints
   `    ✎ nvim  f1.txt, f2.txt, f3.txt +2`. The hint becomes
   `revive to reopen nvim` when no Claude session exists. Rendering runs once
   per adoption, so it is not on the hot path.

### 1.7 Reader: `lib/python/revive.py`

- `Record.nvim_sessions`: the `*.vim` files in `<path minus .rec>.nvim/`,
  without `*.tmp`, with a valid trailer, newest first.
- `session_summary(path)`: parses the first `cd ` line and the `badd +N name`
  lines. Returns basenames and how many files no longer exist, resolved
  against that `cd`.
- `cmd_get` adds field 7, the newest session path, and field 8, a flat
  summary such as `f1.txt, f2.txt +3 · 1 missing · 1 more nvim`.
- `render_list` and `render_here` show the same `✎ nvim` line.
- `cmd_dismiss` removes the ghost's `.nvim` folder with `shutil.rmtree`,
  together with the `.rec` and `pending/`.
- `cmd_prune` removes `.nvim` folders with their ghosts. It also removes
  orphan `.nvim` folders whose `.rec` is gone, and `reopen/` files older than
  one day.

### 1.8 Pick-up: `fish/functions/revive.fish` `_revive_pick`

Order: Claude session, then nvim session, then command.

`_revive_pick` dismisses straight after `get`, before the `cd` and every
branch, and dismiss now deletes the `.nvim` folder. So the move happens first,
for every branch:

```
set -l line (_revive_py get $target); or return 1
… parse fields 1-6 as today, plus nvsess=$parts[7], summary=$parts[8]
set -l keep ""
if test -n "$nvsess"; and test -f "$nvsess"
    set keep (_revive_root)/reopen/(path basename $nvsess | string replace -r '\.vim$' '')-(date +%s).vim
    mkdir -p (path dirname $keep); and mv -f $nvsess $keep; or set keep ""
end
_revive_py dismiss $target >/dev/null      # unchanged position
… story, cd: unchanged, except the story is `nvim` when $keep is set and no Claude session
if Claude session
    test -n "$keep"; and echo "  nvim was open too: $summary — nvim -S $keep"
    _ccs_resume_entry …; return            # $keep stays; prune removes it after 1 day
end
if test -n "$keep"
    echo "  nvim had open: $summary"
    read -l -P "Reopen them in nvim? [Y/n] " answer; or return 0
    if test -z "$answer" -o "$answer" = y -o "$answer" = Y
        nvim -S $keep                      # the wrapper: new pane session + restart loop
        command rm -f $keep
        return
    end
    command rm -f $keep                    # `n`: the user said no to these files
end
… existing "Run it again? [Y/n]" for the command (so `n` still offers `v`)
```

- `path basename`/`dirname` are fish builtins. `mkdir`, `mv` and `date` fork,
  but this is an interactive verb, not the hot path.
- The journal story becomes `nvim`, because the session path will be gone.
  A crash inside the reopened nvim leaves a ghost whose own `.nvim` folder is
  current.
- After a Claude resume, the hint gives the `reopen/` path. That file stays
  until `revive prune`, which removes `reopen/` files older than one day.
- After `n`, the file is deleted at once.

### 1.9 Required fix outside revive: the welcome screen

- `nvim/init.lua` has a `VimEnter` autocmd. When `argc() == 0`, it runs
  `enew` and shows "Welcome back Commander".
- `-S` is sourced before `VimEnter`. A session with no file arguments leaves
  `argc() == 0`, so the welcome buffer replaces the restored current window.
  **[verified]**: under the real config, tab 2 came back as a `nofile`
  buffer, while `-u NONE` restored `f3.txt`.
- Guard: `if vim.fn.argc() == 0 and vim.v.this_session == ''`. Every session
  sets `v:this_session` on line 3 **[verified]**.
- **[verified]** with an emulated autocmd under `-u NONE`: with the guard,
  `-S` restored `f3.txt`, and a bare `nvim` still showed the welcome buffer.
  The edited `init.lua` itself was not run.
- The existing `SessionRestart` path (`nvim.fish` restart loop, `-S` on
  `~/.local/share/nvim/session.vim`) has the same bug today **[inferred]**,
  and this guard fixes it too.

### 1.10 Docs

Update docs/revive.md:
- the store table;
- a lifecycle row for nvim;
- "Picking a ghost up" gets a third branch;
- a short "nvim sessions" section on the wrapper-scoped variable, the unset,
  and the durability order.

Add one clause to the `revive` row in CLAUDE.md.

### 1.11 Tests (run with `cmds test …` only)

**Harness (`tests/fish/conftest.py`).**
- Add `run(…, powercut=True)`. It SIGKILLs every descendant of the shell
  (`ps -A -o pid=,ppid=` walk), then the shell, before closing the pty.
- Today's harness kills only fish. The pty then closes, nvim gets SIGHUP and
  `VimLeavePre` deletes the session. **[verified]**: the "SIGHUP only" case
  left an empty folder. Without this option, every nvim power-cut test would
  test the wrong death.
- Default `False`, so existing tests are unchanged.
- Also set `XDG_DATA_HOME` and `XDG_CONFIG_HOME` to scratch, so test nvims
  write no shada or undo into the real home.

**Pty wiring: `tests/fish/test_revive_nvim.py`, component `fish`.**
- Test nvims run `nvim -u <test init>`. The test init only `require`s
  `nvim/lua/revive_session.lua` from the checkout, so no plugins load.
- The `nvim` wrapper is sourced from the checkout.

| Case | Expect | Prototype |
|---|---|---|
| nvim, `:vsplit f2`, `:tabnew f3`, power cut, next shell | `ghosts/<key>-<epoch>.nvim/<pid>.vim`, trailer, 3 `badd` | passed |
| `:qa` | folder empty | passed |
| `exit` from fish after nvim | no `live/<key>.nvim` | not run |
| `command nvim f` | nothing written | passed |
| `:!printenv REVIVE_NVIM_DIR` inside owner | exit 1 (unset) | passed |
| `GIT_EDITOR=nvim git commit` at the prompt | nothing written | passed |
| nested fish in `:terminal`, then nvim | only the outer session, `badd f1` | passed |
| stale file + a finished command | postexec removes it | not run |
| ghost with session, `revive`, answer `y` | stub `nvim` function records `-S reopen/…` | not run |
| same, answer `n` | falls through to "Run it again?" | not run |

The harness could not stop nvim with a raw Ctrl-Z byte: nvim stayed in state
`S+` and `^Z` was echoed **[verified]**. The two-nvim case therefore goes to
the reader tests, or uses `kill -TSTP <tui pid>` **[unverified]**.

Cost: the prototype cases take 4–8 s each. Ten cases add about a minute to the
`fish` component, which already takes about 2 min.

**Reader: `tests/lib/python/test_revive.py`.**
- The newest valid session is chosen. `*.tmp` and files without the trailer
  are skipped.
- `get` has 8 fields, and fields 7 and 8 are empty when there is no session.
- The summary counts missing files against the `cd` line.
- Dismiss removes the `.nvim` folder.
- Prune removes ghost folders, orphan folders and old `reopen/` files.

**nvim module, headless: new `tests/nvim/test_revive_session.py`.**
- Register it in `COMPONENTS` in `lib/python/run_tests.py`, or it never runs.
- Skip it when `nvim` is not on the PATH.
- Cases:
  - after a save, `&sessionoptions` and `v:this_session` are unchanged;
  - terminal, help, quickfix, unnamed and named `nofile` buffers are absent
    from the file, with their windows. A named `nowrite` buffer keeps its
    window but has no `badd` (both as seen in 2, plugin windows);
  - every buffer's `buflisted` is back after a save;
  - nothing is written while `g:SessionLoad` is set;
  - an unchanged state does not replace the file (same inode);
  - an empty variable means no autocmds;
  - `VimLeavePre` removes the file and the tmp file.
- Also one restore test under the real config: a session with no arglist keeps
  its current buffer. Skip it if `~/.config/nvim/plugged` is missing.

---

## 2. Critique

**`sessionoptions` and plugin windows.**
- Default here is `blank,buffers,curdir,folds,help,tabpages,winsize,terminal`
  **[verified]**.
- The save uses `buffers,curdir,folds,tabpages,winsize` and puts the user's
  value back afterwards. Without `blank`, windows with no file are dropped:
  terminal, quickfix, help and unnamed windows **[verified]**.
- Named `nofile`, `nowrite` and `acwrite` buffers still survive: undotree,
  the conjure log (set `nofile` by `NotFiles()`), vimfiler and
  `fugitive://` windows. They come back as `badd` entries, and as windows
  holding empty buffers of the same name **[verified]**. A `fugitive://`
  window reloads through fugitive **[unverified]**.
- The plan unlists `buftype ~= ''` buffers during the save. **[verified]**,
  headless:
  - a named `nofile` buffer (undotree-like) loses both its `badd` and its
    window;
  - a named `nowrite` buffer (fugitive-like) loses its `badd`, but its window
    still comes back.
- Unlisting changes live buffer state for the length of one `mksession`
  (0.2 ms). No redraw can happen in between, but plugins with `OptionSet` or
  buffer-list hooks may see it. The effect on airline's tabline is
  **[unverified]**.
- Floating windows (telescope, FTerm, which-key) are not saved **[verified]**:
  4 live windows, one of them a float, came back as 2. The other was the
  dropped `nofile` window.
- *Partly handled.*

**Terminal buffers.**
- With `terminal` in `sessionoptions`, a restore runs `edit term://…//<pid>:<cmd>`,
  which re-runs the command. **[verified]**: a `touch marker` inside
  `:terminal` ran again on `-S`.
- That breaks revive's rule that it never runs a command without asking.
- `terminal` is excluded, so terminal windows are lost on restore. vims
  snippet terminals are lost too. *Handled, by giving them up.*

**Unnamed and modified buffers.**
- Unnamed buffers are not in any session, and their text is lost.
- Named modified buffers are written by `AutoSave` within about 200 ms of a
  pause, with `fsync`. So at most the last pause's typing is at risk, as it
  is today.
- Persistent undo is on, so undo history survives. *Not handled for
  unnamed text. No change from today.*

**Help and quickfix windows.**
- Both are dropped (no `help`, no `blank`).
- A quickfix list cannot be restored by a session anyway.
- *Handled, by dropping them.* Keeping `help` would cost nothing. See Q4.

**Swap-file prompts after a crash.**
- `noswapfile` is set (`settings.vim`), so `-S` after a crash raises no
  ATTENTION prompt. *Handled, by existing config.*
- If `swapfile` is ever turned back on, every restore after a crash will stop
  on a prompt for each file. The plan does not guard against that. Passing
  `-n` would.
- `~/.local/share/nvim/swap/` exists, so swap files were on at some point.

**Several nvim instances in one pane.**
- `:terminal` → nested fish → nvim: the nested fish has an empty
  `$__revive_rec`, and the owner already unset the variable. *Handled*
  **[verified]**.
- Nested interactive fish at the prompt: same. The outer record shows `fish`
  running, and the inner nvim is not saved. *Not handled. It matches the
  journal's own nested-shell rule.*
- `git commit` / `jj describe` at the prompt: the binary is run by git or jj,
  not by the wrapper. *Handled* **[verified]** for git; jj **[inferred]**.
- `:!git commit` inside nvim: the variable was unset. *Handled*
  **[verified]** for `:!`.
- `cmds` subshells: a fresh non-interactive fish has an empty
  `$__revive_rec`. *Handled*, and also *not tracked*.
- Ctrl-Z'd nvim plus a second nvim: one file each.
  - The newest is the foreground nvim, because a stopped nvim cannot save.
  - Postexec keeps both while `jobs -q` is true.
  - *Handled*, but **[unverified]** in a pty (see 1.11).
  - When the second nvim exits cleanly, it deletes only its own file.
- Fish's Alt-E (`edit_command_buffer`) and `funced` run `$EDITOR`, which
  resolves to the wrapper. A crash while editing a command line would offer
  to reopen fish's temp file. *Not handled. Rare and harmless: the file is
  gone, and the summary says "1 missing".*
- `command nvim`, `exec nvim`, `xargs nvim` and `fd | xargs -o nvim` are not
  tracked. *Not handled.* See Q2.

**tmux.**
- Each tmux pane's fish has its own key (`<guid>-<n>`) and its own
  `$__revive_rec`, so each gets its own folder. **[unverified]**: not run.
- After a reboot the tmux server and its pane ids are gone. As with the
  journal today, those ghosts never match a new pane. They show only in
  `revive ls` and are picked up by number.
- `tmux new 'nvim'` (no fish in between) is not tracked.

**ssh.**
- Nothing crosses ssh. The variable is local to the wrapper, and a remote
  nvim would write on the remote host.
- The ghost says `running ssh host`, as today. *Not handled. Out of scope.*

**Cost of `mksession`.**
- 0.16 ms for 12 buffers, 3 tabs and 6 windows. 0.27 ms for 30 buffers,
  9 tabs and 25 windows, with a 24 KB file.
- The narrower options cost the same. **[measured]**, headless with the real
  config loaded, 200 runs each.
- The flush costs 4.7 ms, off the main thread **[measured]**.
- Saves are debounced, and identical output is not flushed.
- The postexec stale check costs about 0.03 ms **[measured]**.
- Even one save per second would not be felt. *Not a risk.*

**A session that points at deleted files.**
- `badd`/`edit` of a missing file opens an empty `[New]` buffer, and nothing
  is created on disk **[verified]**, with `-u NONE` only.
- Under the real config, `AutoSave` runs `wa`. That writes only modified
  buffers, so the file is recreated only if the user types into it
  **[unverified]** under the real config.
- The pick-up summary says "N missing" before asking. *Partly handled.*
- A missing `cd` directory gives an E344 message and the load continues
  **[unverified]**. `_revive_pick` already warns when the ghost's cwd is gone.

**The existing Session\* commands and vims.**
- `SessionSave`, `SessionQuit`, `SessionRestart` and `SessionLoad` use one
  global `g:session_file` that is shared across panes. Reusing it here would
  let panes overwrite each other's sessions, so the plan does not.
- The autosave puts `&sessionoptions` and `v:this_session` back after each
  save. `mksession` would otherwise point `v:this_session` at the pane file.
  So `SessionSave` output is unchanged. **[unverified]**: planned test.
- `SessionRestart` quits, so the pane file is deleted. The wrapper's restart
  loop starts a new nvim, which writes a new pane file with its new pid.
- The welcome-screen fix (1.9) repairs the restart path too.
- vims: `vims X` → `vim` → `nvim` wrapper, so a vims nvim is tracked like any
  other. The pane session lacks the vims terminals. On `n`, the pick-up falls
  through to offering `vims X` itself, which brings them back by design.

**Other risks.**
- *`BufEnter * lcd %:p:h`* gives every window a local directory, and
  `curdir` records each one. Restored cursors were correct under the real
  config **[verified]** (f1@500, f2@1200).
- `RememberFolds` runs `loadview` on BufWinEnter, which may override the
  session's fold commands **[unverified]**. Low impact.
- *An nvim that outlives its shell* (fish SIGKILLed while the pty stays open)
  would write into a folder that adoption has moved. Its tmp open fails, so
  it writes nothing. **[inferred]** from the prototype, which creates the
  folder only at setup.
- *Wrong owner after `exec fish`*: the pid is unchanged and
  `$__revive_rec` is rebuilt the same, so it is fine. **[inferred]**
- *Quit during a save.* `VimLeavePre` can delete the file while an async
  fsync and rename are still running. The rename then recreates the file
  after a clean quit.
  - Fix in the module: on `VimLeavePre`, set a `leaving` flag. The rename
    callback then deletes instead of renaming.
  - Until then, only the postexec check removes the file.
- *Postexec check blocked by an unrelated job.* While any job exists, such as
  `sleep 600 &`, the check is skipped and a stale session can survive.
  - It is removed at the first prompt after the jobs end.
  - A crash in between still offers it. *Not handled.* The prompt is
    `[Y/n]`, so the user can refuse it.

---

## 3. Verdict

**The session option is still the right choice.**

- The main objection was durability. It is resolved, because nvim can flush
  before it renames (1.5).
- The real problems are on restore: terminal re-runs, the welcome screen, and
  plugin buffers. Each one was seen, and each has a small, testable fix.
- The fallback (nvim appends `nvimfile` lines to the pane record) avoids new
  files and needs no flush, because it uses the proven append-only path.
- The fallback costs:
  - **Compaction.** `_revive_compact` keeps one line per non-`cmd`/`done`
    key, so it would collapse all file lines into one. It needs a change.
  - **Layout and cursors.** It loses splits, tabs and per-window cursors.
    Restoring cursors for more than one file needs a generated `-c` script,
    which is a small session in all but name.
  - **A second writer.** nvim would write into the fish-owned record, which
    the journal's "two writers interleave" rule was written to avoid. A
    stopped nvim and a running shell make that real.
- Where the fallback wins: plugin buffers and terminals never come back,
  because only real files are listed.
- If the restore problems turn out worse in daily use, the module can switch
  to writing a file list into its own `<pid>.vim` (a generated
  `edit`/`cursor()` script), with no change to the store, adoption or
  pick-up. The design keeps that door open.

**Open decisions**

**Q1 (pick-up order)**: I recommend `yes`.
- **yes:** Claude, then "Reopen nvim? [Y/n]", then on `n` "Run it again?"
  for the command (`v`, `vims X`).
- **no:** say which branch should win or be dropped.

**Q2 (launch coverage)**: I recommend `wrapper`.
- **wrapper:** only nvims started through the `nvim` fish function are
  tracked: `v`, `vim`, `vims`, plain `nvim`. No fork, and no dependence on
  nvim's process layout.
- **global:** export the folder and the shell pid, and walk the parent pids.
  This adds `command nvim` and `exec nvim`. It costs 10 ms per nvim start,
  depends on the 0.11 TUI/server split, and needs extra guards for `:!`
  children.

**Q3 (several nvims in one ghost)**: I recommend `newest`.
- **newest:** reopen the most recently saved one, and list the others with
  their paths.
- **each:** ask about each one in turn.

**Q4 (help windows)**: I recommend `drop`.
- **drop:** help windows are not restored. That is the current plan.
- **keep:** add `help` to the save options. Help windows come back and cost
  nothing.

**Decided 2026-11-14** (the user's session numbered these Q5–Q8):
pick-up order `yes`, launch coverage `wrapper`, several nvims `newest`,
help windows `drop`. Built 2026-11-14. Changes from this plan: `later()` never
puts back a sooner save (CursorHold pushed a 300 ms save to 2 s); events are
off during a save (unlisting fired BufDelete and re-armed it); the pick-up moves
the whole `.nvim` folder to `reopen/<name>-<epoch>/`, so other nvims survive.
