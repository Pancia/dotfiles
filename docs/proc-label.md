# Process Labeling (proc-label)

`bin/proc-label` sets custom process names visible in both macOS Activity Monitor and `ps`.

## Usage

```
proc-label NAME command [args...]
```

## How It Works

1. Uses Python's `setproctitle` to overwrite the process's `argv`/`environ` memory region
2. Activity Monitor reads this region via `proc_info`, so the new name shows up
3. Passes `NAME` as `argv[0]` to the exec'd process, so `ps` also shows the label
4. Calls `os.execvp` to replace itself with the target command (no extra process)

The `setproctitle` modification survives `exec` in Activity Monitor, even though `exec` replaces the process image. `ps` would normally reset to the new binary's name, but since we also set `argv[0]` to the label, both tools show the correct name.

## What Doesn't Work for Activity Monitor

These were tested on macOS and only affect `ps`, not Activity Monitor:

| Method | Affects ps | Affects Activity Monitor |
|--------|-----------|------------------------|
| `exec -a "name"` (bash) | Yes | No |
| `Process.setproctitle` (Ruby) | Yes | No |
| Symlink to binary | No | No |
| Copy binary with new name | N/A | Yes (but wastes disk) |
| Python `setproctitle` | Yes | Yes |
| Node `process.title` | Yes | Yes |

## Usage Patterns

### Python via uv

proc-label goes **inside** `uv run`, not outside. `uv run` spawns a child process -- wrapping uv would label the uv parent, not the worker.

```bash
# Correct: labels the python process
uv run --with setproctitle proc-label my-app python main.py

# Wrong: labels the uv process, python child is still "python3.11"
proc-label my-app uv run python main.py
```

`--with setproctitle` makes the package available in the uv environment without adding it to `pyproject.toml`.

### Python without uv

If the system python3 has setproctitle installed (`pip3 install setproctitle`):

```bash
proc-label my-app python3 main.py
```

If not, wrap with uv to provide it:

```bash
uv run --with setproctitle proc-label my-app python3 -m http.server 8420
```

### Non-Python binaries (claude, etc.)

Works directly -- proc-label sets the title then execs into the binary:

```bash
proc-label "claude [project]" claude --resume
```

### Ruby (cmds)

`bin/cmds` re-execs itself through proc-label using an env guard to prevent infinite loops:

```ruby
if !ENV['CMDS_LABELED']
  ENV['CMDS_LABELED'] = '1'
  exec("proc-label", "cmds:#{cmd_name} [#{dir_name}]", "ruby", $0, *ARGV)
end
```

### Node.js

Node has built-in `process.title`. No need for proc-label -- just add to the entry point:

```javascript
process.title = 'my-app';
```

## Currently Labeled Processes

| Process | Where label is set |
|---------|--------------------|
| claude sessions | `fish/functions/my-claude-code-wrapper.fish` |
| cmds (all invocations) | `bin/cmds` (self-labeling) |
| asmr-board | `cmds/.../asmr-board/cmds.rb` |
| lakshmi (cmds) | `cmds/.../lakshmi/cmds.rb` |
| pymodoro | `bin/pymodoro` |
| youtube-transcribe | `services/youtube-transcribe/dotfiles-services-youtube-transcribe.sh` |
| wget-server | `services/wget_server/script.sh` |
| lakshmi (service) | `services/lakshmi/script.sh` |
| copyparty | `services/copyparty/script.sh` |
| tv-board | `process.title` in `~/projects/TVBoardApp/server.js` |
| bookmark-manager | `process.title` in `~/projects/bookmarks_manager/vite.config.js` |

## Why setproctitle Works

On process start, the kernel maps `argv[]` and `environ[]` into a contiguous memory region. `setproctitle`:

1. Copies environment strings to heap memory (so they're not lost)
2. Overwrites the original kernel-mapped `argv`/`environ` region with the new title
3. Activity Monitor reads this region via `proc_info` / `PROC_PIDINFO`

This is distinct from what `ps` reads (`argv[0]` of the current process image), which is why `exec -a` and Ruby's `Process.setproctitle` (which modify `argv[0]`) only show in `ps`. Python's `setproctitle` modifies the deeper kernel-visible memory, which is what Activity Monitor inspects.
