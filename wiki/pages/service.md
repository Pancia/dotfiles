# service — launchd-backed background services

A Ruby CLI at `~/dotfiles/bin/service` (on PATH) for managing my personal
`org.pancia.*` launchd agents (inari bots, sanctuary, copyparty, syncthing, …).
Each service lives in `~/dotfiles/services/<name>/` (a `.plist` + a wrapper +
`script.sh`) and logs to `~/.log/services/<name>.log`.

Names are accepted short or full: `inari` == `org.pancia.inari`.

## Commands

```
service list                          # launchctl list, filtered to org.pancia
service status                        # table: SERVICE / PID / STATUS / LAST START / AGO
service start   <name>
service stop    <name>
service restart <name> [--log FLAGS]  # --log/-l shows the log after restarting
service log     <name> [FLAGS]        # see below
service create  <name>                # scaffold a new service dir + plist + script
service edit    <name>                # $EDITOR on the service's script + plist
```

Global: `-h/--help`, `-v/--verbose`, `-n/--dry-run`.
Per command: `service log --help`, `service restart --help` (lists the log flags
with descriptions; also drives `service --fish-completions`).

## `service log` — interactive **and** scriptable

By default `service log <name>` opens the live log in `less +GF` (follow mode,
Ctrl-C or `q` to stop) — good for a human watching in a terminal.

It also auto-detects when it's **not** attached to a terminal (piped, or run by
an agent/script) and switches to a **snapshot**: it prints the last N lines and
exits instead of hanging in a pager. You can force that with `-p`.

Flags work **before or after** `<name>` (`log -q inari` == `log inari -q`):

| Flag | Effect |
|------|--------|
| `-p`, `--print` (`--no-follow`) | Non-interactive: print the last N lines and exit. |
| `--lines N` (`--tail N`) | How many lines the snapshot shows (default **200**). |
| `-q`, `--quiet` | Hide known polling noise (Telegram long-poll `getUpdates` / httpx lines — see `LOG_NOISE` in the script). |
| `--grep PAT` | Keep only lines matching the extended-regex `PAT`. |
| `--exclude PAT` | Drop lines matching the extended-regex `PAT`. |

Any filter (`-q`/`--grep`/`--exclude`) implies non-interactive **unless** you're
in a terminal — in a terminal, a filter switches to a **live filtered follow**
(`tail -f | grep --line-buffered …`) so you can watch clean logs in real time.

### Examples

```
service log inari                       # live follow in less (human)
service log inari -q                     # live follow, noise filtered (human)
service log inari -p --lines 80          # last 80 lines, print & exit (agent-friendly)
service log inari -q -p                   # last 200 meaningful lines, no poll noise
service log inari --grep 'Error|Traceback|Exception' -p   # just the errors
service log inari --exclude apscheduler -p
```

Agents: prefer `service log <name> -q -p` (or add `--grep`) — it never blocks on
a pager and drops the getUpdates spam that otherwise buries real events.

## `service restart <name> --log` — same flags

`restart` accepts the **entire** `service log` flag set after `--log`/`-l`, and
hands them straight to the log viewer once the service is back up:

```
service restart inari --log                    # restart, then follow in less
service restart inari --log -q                 # restart, then live follow, noise filtered
service restart inari --log -q -p --lines 50   # restart, print 50 clean lines, exit
service restart inari --log --grep 'Error|Traceback' -p
```

Passing any log flag implies `--log`, so `service restart inari -q -p` works too.
As with `log`, a non-TTY (agent, pipe) always gets a snapshot instead of a pager
— which makes `restart --log -q -p` the natural "bounce it and show me what
happened" one-liner.

## Implementation notes

- Both subcommands **declare** the log flags on their own `OptionParser`
  (`add_log_flags`), which is what fills in `service log --help` /
  `service restart --help` and `service --fish-completions`.
- The CLI framework (`lib/ruby/cli.rb`) parses each subcommand with `order!`,
  which **stops at the first positional** (`<name>`). So flags *before* the name
  are captured by the declared switches (which re-emit them into a `pre` array),
  and flags *after* the name arrive verbatim in the handler's `*args`. Both get
  concatenated and parsed by `parse_log_args` — that's why either position works.
- `view_log!` is the single implementation shared by `log` and `restart --log`;
  it `exec`s, replacing the process, so the pager/`tail -f` owns the terminal.
- The snapshot pipeline filters the **whole** file with `grep`, then `tail -n N`,
  so you get the last N *meaningful* lines (not N raw lines that might all be
  noise). The live path adds `--line-buffered` so filtered output isn't stuck in
  a buffer.
- New noise patterns: add to the `LOG_NOISE` array near the top of the script.
