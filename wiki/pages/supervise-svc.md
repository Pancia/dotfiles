# supervise / svc — restartable, human-owned dev services

Two small bash tools in `~/dotfiles/bin/` (on PATH). They let a long-lived dev
process (REPL/nREPL server, file watcher, etc.) stay **started and owned by my
terminal** — my TTY, my Ctrl-C, output in my pane — while an LLM/tool can
**restart it on demand** without owning it.

The split:
- **`supervise`** — I run it (usually from a `cmds` entry) to launch the process.
- **`svc`** — the LLM/tool surface: inspect, restart, or stop a supervised
  process. It **never starts** one (that's mine).

## Commands

```
supervise [--keep] <name> -- <command> [args...]   # I run this (foreground, my terminal)

svc status [<name>]      # pid / alive / readiness (up|down|wedged|n/a) + prev exit
svc logs   <name> [-n N] # tail .run/<name>.log (captured stdout+stderr)
svc restart <name>       # SIGHUP the supervisor -> respawn in my pane, wait until serving
svc stop    <name>       # SIGTERM the supervisor -> stop it
```

Run `svc` from the project root. `--keep` makes `supervise` auto-respawn on any
exit (default: stop and stay visible on crash).

## Per-project config

`supervise`/`svc` are generic. Project specifics come from `.svc.conf` and/or
`.svc.local.conf` in the project root, sourced in that order (`*.local.*` is
git-ignored, so use it for personal/uncommitted setup). Define:

```bash
SVC_SERVICES="server browser test_repl"     # names for `svc status` with no arg

# name -> readiness/port file (optional). supervise clears it on restart/exit so
# a stale port can't mislead the next client; svc uses it for up/down + wedged.
svc_port_file() {
  case "$1" in
    server)    echo .nrepl-port ;;
    test_repl) echo .nrepl-test-port ;;
    browser)   echo .shadow-cljs/nrepl.port ;;
  esac
}

# eval/probe against a service; exit 0 if it answers. $1 = the port file (optional).
# With it, status distinguishes up vs wedged and restart waits for a real
# round-trip; without it, a TCP connect to the port is the readiness signal.
svc_eval() { ./scripts/clj-nrepl-eval-wrapper -f "$1" '(+ 1 2)' >/dev/null 2>&1; }
```

No config → `supervise` is just a plain supervisor and `svc` reports
running/not-running only.

## How it works (the load-bearing details)

- **Ownership**: launched via `exec supervise …` from a `cmds` entry, so the
  supervisor is the terminal's foreground process. Ctrl-C tears it down.
- **Restart** = `svc restart` sends **SIGHUP** to the supervisor, which kills the
  child's **whole process group** (needed when the command is a launcher that
  forks the real process, e.g. a node CLI that spawns a JVM — a single-PID TERM
  would orphan the grandchild), waits for it to fully die (escalating to KILL),
  then respawns in place. The supervisor PID never changes.
- **Restart confirmation**: `svc` waits for the supervisor's generation counter
  (`.run/<name>.gen`) to advance **and** for the service to actually answer
  (`svc_eval`, with a ~5s watchdog) before reporting "back up" — so it never
  mistakes a still-dying old instance for the new one.
- **Crash surfacing**: on an unexpected exit the supervisor stops, writes
  `.run/<name>.status` (`rc=N <date>`), and clears the port file so the next
  client fails fast. `svc status` shows `prev exit:`; `svc logs <name>` has the
  stacktrace. (`ready=wedged` = port open but probe timed out → hung; restart it.)
- **stdin caveat**: the child's stdin is a held-open FIFO (so a REPL prompt
  reading stdin blocks idle instead of taking SIGTTIN under job control). You
  **can't type into the terminal REPL** — drive the process via its socket/nREPL.
- **State** lives under `.run/` (`.pid`, `.gen`, `.log`, `.status`, `.stdin`) — gitignore it.

## LLM contract

- Restart a wedged/crashed/needs-classpath-reload service with
  `svc restart <name>`; diagnose a failed connection with `svc status` then
  `svc logs <name>`.
- **Never start** a service — if `svc restart` says "not running", ask the human
  to start it (`cmds <name>`).

## Adding it to a new project

1. Drop a `.svc.conf` (committed/shared) or `.svc.local.conf` (personal) with
   `SVC_SERVICES` + `svc_port_file` + optional `svc_eval`.
2. Launch services via `supervise <name> -- <cmd>` (typically a `cmds` entry).
3. Gitignore `.run/`.

That's it — the scripts themselves are identical everywhere (single source of
truth in `~/dotfiles/bin/`).
