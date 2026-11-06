# supervise / svc / svc-tmux — restartable dev services

Three small bash tools in `~/dotfiles/bin/` (on PATH). They let a long-lived dev
process (REPL/nREPL server, file watcher, etc.) run **in a terminal pane** — its
TTY, its Ctrl-C, output in the pane — while an LLM/tool can **restart it on
demand** without owning it.

The split:
- **`supervise`** — runs one process in the pane it was started from (usually a
  `cmds` entry). Keys and a status bar in that pane.
- **`svc`** — the control surface: inspect, restart, suspend, stop a supervised
  process, wherever it runs. It **never starts** one.
- **`svc-tmux`** — the way a script or an LLM **starts** services: each one runs
  under `supervise` in a window of a dedicated tmux server.

## Commands

```
supervise [--keep] <name> -- <command> [args...]   # foreground, this terminal
supervise [--keep] <name>                          # command from svc_cmd (see config)

svc status [<name>]      # pid / alive / readiness (up|down|wedged|n/a) + prev exit
svc status --short       # one line from state files only, e.g. "● server  ○ test_repl"
svc logs   <name> [-n N] # tail .run/<name>.log (captured stdout+stderr)
svc restart <name>       # respawn the child in its pane, wait until serving
svc suspend|resume <name>  # drain the child to free RAM / respawn it
svc stop    <name>       # stop it (and its supervisor)
svc -C <dir> ...         # as if run from <dir>

svc-tmux up [--wait] [--timeout S] [name...]   # start what isn't running (idempotent)
svc-tmux attach                                # look at them (one window per service)
svc-tmux down [name...]                        # stop the ones hosted in tmux
svc-tmux ls                                    # one line per service + where it runs
```

Run `svc` / `svc-tmux` from the project root. `--keep` makes `supervise`
auto-respawn on any exit (default: stop and stay visible on crash).

### Keys in the supervised pane

While `supervise` runs in a terminal, single keys control it — no Enter needed:

| Key | Action |
|-----|--------|
| `r` | restart (resumes instead, if suspended) |
| `s` | suspend / resume |
| `c` | clear the screen |
| `q` | quit — stop the service and the supervisor (same as Ctrl-C). **Under tmux:** stop the service but keep the window — the bar says `stopped · r or s to start`. Ctrl-C still exits |
| `?` `/` `h` | open / close the help panel above the bar (Esc also closes) |

Nothing the keys do is printed into the process output: a pending action shows
in the bar (`restarting...`) until the new state arrives, and the help panel
takes rows from the bottom of the scroll region (scrolling output up first so
nothing is covered) and hands them back when closed.

The bottom row of the pane is a status bar: name, state (`starting` until the
port file exists, `up`, `suspended`, `stopping...`), child pid, port and uptime,
plus the keys. A scroll region keeps child output above it; the bar is redrawn
on every change and every 5s, and re-placed on resize. A child that resets the
scroll region itself (a full-screen TUI) would scroll over it — REPLs don't.

**Scrollback caveat.** Terminals discard lines that scroll out of a partial
scroll region unless told otherwise. iTerm2: Profiles → Terminal → *Save lines to
scrollback when an app status bar is present* (`"Scrollback With Status Bar"`),
off by default — without it, the pane has no scrollback and the mouse wheel does
nothing. **Turn it on** (done on this machine 2026-11-05). tmux keeps them as
long as the region starts at row 1, which this one does.

Each key sends the same signal `svc` sends, so both take the identical path.
`SUPERVISE_KEYS=0` turns the keys and the bar off. The pane runs with tty echo off, and the
original mode comes back on exit (after a `kill -9` of the supervisor, run `reset`).

## Per-project config

`supervise`/`svc` are generic. Project specifics are sourced, in order, from
(`lib/svc/conf.sh`):

1. `.svc.conf` in the project root — committed with the project.
2. `~/Vaults/work-config/fs-config/<project path>/svc.conf` — **private and backed
   up**: the work-config vault, next to the project's private `cmds.rb`. The path
   key is tried logical (as `cd` shows it) then physical, the same order `cmds`
   uses. `SVC_FS_CONFIG` overrides the root.
3. `.svc.local.conf` in the project root — git-ignored, machine-local overrides.

Festivar's lives in (2). Define:

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

# name -> command line, run with `bash -c` (optional; needed for svc-tmux and for
# `supervise <name>` with no command). Put setup here, not in the caller's shell:
# a service started by svc-tmux gets a clean environment.
svc_cmd() {
  case "$1" in
    server) echo 'exec clojure -A:dev:local/nREPL' ;;
  esac
}

# once per supervisor, before the first spawn (optional). Runs in supervise's own
# shell, so its exports reach every respawn: fetch credentials here, not in
# svc_cmd, or each restart fetches them again.
svc_setup() {
  case "$1" in
    server) eval "$(./scripts/awsenv me)"; export JAVA_HOME=/opt/... ;;
  esac
}

# caller env vars copied into each svc-tmux window (optional)
SVC_ENV="AWS_PROFILE"
```

No config → `supervise` is just a plain supervisor and `svc` reports
running/not-running only. Names only need to be unique **within** a project:
all state is under the project's own `.run/`.

## How it works (the load-bearing details)

- **Ownership**: launched via `exec supervise …` from a `cmds` entry, so the
  supervisor is the terminal's foreground process. Ctrl-C tears it down.
- **Protocol "p2"** (pidfile field 3): a request is `.run/<name>.req`
  (`restart`/`suspend`) + SIGUSR1; SIGUSR2 resumes; **SIGHUP means the terminal
  went away** (pane, tab or tmux window closed) and stops the service. Before p2,
  HUP meant restart — and a closed pane then died mid-restart on the dead tty,
  orphaning the JVM with no pidfile. `svc` still sends HUP to a pre-p2
  supervisor, so old ones keep working until restarted.
- **No exit orphans the child**: the EXIT trap drains the process group whatever
  the path (a set -e failure included), and pane output goes through `say`, which
  never fails.
- **Single instance**: the pidfile check-and-claim runs under a `mkdir` lock
  (`.run/<name>.lock`, held for milliseconds), so two racing starts — `svc-tmux up`
  vs. a hand-run `cmds server` — can't both win.
- **Restart** = the supervisor kills the child's **whole process group** (needed when the command is a launcher that
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
  The pane's keys go to the supervisor's key reader instead (see above).
- **Key reader**: started with job control off, so it shares the supervisor's
  foreground process group and may read the tty. Every `stty` call also runs
  with `set +m`: under job control it would get its own process group, and its
  `tcsetattr` would fail with EINTR. Cleanup reaps the reader *before* it
  restores the tty, because a dying `read -n1` restores the mode it saved.
- **State** lives under `.run/` (`.pid`, `.gen`, `.log`, `.status`, `.stdin`,
  `.req`, `tmux-session`) — gitignore it.

## svc-tmux (how scripts and LLMs start services)

- **Own server**: `tmux -L svc`, config `lib/svc/tmux.conf` (remain-on-exit,
  mouse, 50k history). Your normal tmux is never touched.
- **Scrubbed env**: whoever starts the server fixes every window's base env, so
  it starts with the caller's env minus session-bound variables (`CLAUDE*`,
  `CCS_*`, `AI_AGENT`, `TMUX*`, terminal-session ids) — an LLM starting it doesn't
  hand its identity to every service. A denylist, not an allowlist: the first
  version kept only HOME/PATH/LANG..., dropped `XDG_CONFIG_HOME`, and clojure
  then silently lost the `:local/nREPL` alias from `~/.config/clojure/deps.edn`.
  `SVC_ENV` names are copied in per window. A server started before an env fix
  keeps its old env: `tmux -L svc kill-server` and start again.
- **Your tmux bindings**: `lib/svc/tmux.conf` sources `~/.config/tmux/tmux.conf`
  first (prefix, mouse, plugins), then its own settings.
- **One session per project**: `svc-<dir>-<hash of realpath>`, always targeted
  with `=` (exact), so `proj` and `proj.one` never collide.
- **Idempotent**: `up` skips a service that runs anywhere — including a `cmds`
  pane — and `down` only stops the ones hosted in its session.
- **`up --wait`** returns 0 only when every service answers and stays up for 2s
  on the same generation (so a crash right after start is caught); a pane that
  dies fails at once with its last lines. A crashed pane stays readable
  (`remain-on-exit`); the next `up` respawns it.
- **Windows**: a clean exit (Ctrl-C, `svc stop`, `down`) closes the window; a
  crash keeps it, error on screen, with a `<name> crashed (exit N) · svc-tmux up
  <name> to restart` line (`remain-on-exit failed` + `remain-on-exit-format`).
  `q` doesn't exit at all there (see Keys). `prefix s` / `prefix w` open the
  chooser with every service window showing.
- `svc-tmux attach` nests when run inside tmux (it's a different server).
- Server start costs ~3s (your tmux.conf's tpm `run` is synchronous) — once per
  server. Tests point `SVC_TMUX_CONF` at a copy without it.

## LLM contract

- Restart a wedged/crashed/needs-classpath-reload service with
  `svc restart <name>`; diagnose a failed connection with `svc status` then
  `svc logs <name>`.
- **Start** a service only with `svc-tmux up --wait <name>` (needs `svc_cmd` in
  the project's config) — never run `supervise` yourself: it would belong to your
  shell and die with it. If there is no `svc_cmd`, ask the human (`cmds <name>`).
- Stop only what you started: `svc-tmux down <name>`.

## Adding it to a new project

1. Drop a `.svc.conf` (committed/shared) or `.svc.local.conf` (personal) with
   `SVC_SERVICES` + `svc_port_file` + optional `svc_eval` + `svc_cmd`.
2. Launch services via `supervise <name>` (typically a `cmds` entry) or
   `svc-tmux up`.
3. Gitignore `.run/`.

Tests: `cmds test svc` (`tests/svc/`).

That's it — the scripts themselves are identical everywhere (single source of
truth in `~/dotfiles/bin/`).
