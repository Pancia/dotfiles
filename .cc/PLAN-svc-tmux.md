# PLAN: svc-tmux — host a project's supervised services in one tmux session

Status: **implemented 2026-11-05** — Phase 0 + wrapper as below; tests in
`tests/svc/` (`cmds test svc`). Decisions taken: restart = `.req` file + USR1
(HUP = terminal gone); `svc_cmd` runs via `bash -c`; name `svc-tmux`; `down`
kills the session once no live panes remain. Additionally: `up --wait` requires
2s of stable readiness (a probe-less service is otherwise "up" the instant its
child exists), and `svc _ready` checks the child, not just the supervisor. Revised after a review that
tested the claims on a private tmux server; findings marked (V) were verified
by experiment or code, (R) reasoned.

## Goal

Start, see and stop all of a project's `supervise` services in one place, and
let a script or an LLM start them — today only a human can, from a `cmds` entry.

## Shape

A wrapper, not a change to `supervise`'s role. `supervise` stays the primitive
(one process, signals, `.run/` state, in-pane keys and bar) and keeps working in
any terminal. `svc-tmux` only decides *where* each `supervise` runs.

```
svc-tmux up [--wait] [name...]  # start missing services (idempotent); --wait = until serving
svc-tmux attach                 # attach (switch-client when already inside tmux)
svc-tmux down [name...]         # svc stop each, wait for exit, kill session when no live panes
svc-tmux ls                     # session + one line per service
```

## Phase 0 — prerequisite fixes in `supervise` (bugs today, not wrapper work)

1. **A closed pane orphans the child (V).** Closing the terminal (tmux
   `kill-session`/`kill-window`, `respawn-pane -k`, very likely closing an iTerm
   tab) sends SIGHUP, which `supervise` treats as *restart*. The next `echo >&2`
   hits the dead pty, `set -e` exits, and `cleanup` removes `.pid`/`.gen` without
   draining — the JVM is reparented to launchd and `svc status` says "not
   running". Fix: move `svc restart` off HUP to its own signal (keep HUP = "tty
   gone": drain and exit); make `cleanup` drain the child; make the stderr echoes
   `|| true`.
2. **No-argument `supervise <name>` would be invisible (V).** `is_supervise` and
   `svc`'s `live_sup` match `"supervise $name "` with a trailing space, which
   `ps` lacks when name is the last argv. Match against `"$cmd "` instead, and
   read `.svc.conf` before the "no command given" check so `svc_cmd` can supply it.
3. **The single-instance guard races (V).** Three concurrent starts all passed the
   pidfile check; once the pidfile ended up naming a dead loser while the real
   supervisor ran unseen. Take an atomic lock (`mkdir .run/<name>.lock`, or a
   noclobber write) before writing any state.

## Config: where the command comes from

New optional hook in `.svc.conf` / `.svc.local.conf`:

```bash
svc_cmd() { case "$1" in server) echo "clojure -M:dev:nrepl" ;; ... esac; }
```

`supervise <name>` with no `-- cmd` runs it (decide: `bash -c` of the string, so
quoting is the config's job). The `cmds` entry becomes `exec supervise server`,
one source of truth for both launch paths. Parsing `cmds.rb` is rejected: it is a
human command file whose entries also run setup (`awsenv`, `JAVA_HOME`, ...).
That setup moves into `svc_cmd` or a sourced env file.

## Wrapper design

- **Dedicated tmux server:** `tmux -L svc -f <own minimal conf>`. Leaves the
  user's main server and its plugins alone.
- **Clean environment (V).** *(Implemented as a denylist after the allowlist
  dropped XDG_CONFIG_HOME and broke clojure aliases — see the wiki.)* Every window inherits the env of whoever started the
  tmux *server*; later callers' env is ignored. Started by an LLM, every window
  got `CLAUDECODE`, `CLAUDE_CODE_SESSION_ID`, `CLAUDE_CODE_MESSAGING_TOKEN` and
  `CCS_ENTRY_FILE` — a later human `claude` there would inherit the ccs identity.
  Start the server under `env -i` + a login shell, then pass `-e VAR=...` only for
  names in `SVC_ENV`. Caveat: an LLM's shell may lack the human's auth tokens, so
  services that need them should fetch them in `svc_cmd`, not rely on the caller.
- **Session names (V).** `svc-proj.one` becomes `svc-proj_one`; `-t svc-proj`
  prefix-matches `svc-proj_one`; two same-named dirs would share (and `down`
  each other's) session. Name sessions `svc-<dirname>-<short hash of realpath>`,
  record it in `.run/tmux-session`, and always target `=name` (exact match).
- **Windows:** one per service, `new-window -c "$PWD"` (supervise finds `.run/`
  and `.svc.conf` from its cwd), `remain-on-exit on` so a crash stays readable.
  Respawn a dead pane with `respawn-pane` — never `-k` (it HUPs a live one).
- **`up --wait` is the LLM contract (R).** Returns nonzero, and prints the tail of
  `svc logs`, if the pane dies or the service is not serving within the timeout
  (reuse `svc`'s `confirmed()`). Plain `up` returns once windows exist.
- **`down` (R):** `svc stop` only sends TERM; wait until each pidfile is gone
  (drain can take ~10s). "Empty" = no live panes (`#{pane_dead}`), since
  `remain-on-exit` keeps dead ones.
- **Status line (R):** optional `status-right` with a new `svc status --short`
  that reads only pid/gen/port files — no `svc_eval` (a clojure eval with a 5s
  watchdog, per service, every few seconds is too heavy) — and takes the project
  dir explicitly, since it runs in the tmux server's cwd.
- **In-pane bar:** works in tmux, and tmux keeps history with the region set (V,
  `history_size=173`). Only iTerm drops it (its "Save lines to scrollback when an
  app status bar is present" setting). Keep the bar as is.
- **Lifetime:** services survive closing the terminal — the point, but a real
  difference from the in-pane mode; `ls` must make it obvious what still runs.

## Starting rule changes

An LLM or script may start a service **only through `svc-tmux up --wait`**, never
by running `supervise` directly (it would bind to the LLM's shell and die with
it). `svc restart` on a stopped service says "`svc-tmux up <name>`". Update the
wiki page and the global CLAUDE.md `svc` section.

## Tests

New `tests/svc/` component, registered in `COMPONENTS`. Use
`tmux -L test -f /dev/null` (the real tmux.conf loads plugins), killed in teardown.

- Process-level (the risks above): after kill-session / kill-window no orphaned
  child, and `svc status` agrees with `ps`; concurrent `up` + a direct
  `supervise`; dotted and prefix-colliding project names; the env the server
  got when an LLM-like env started it; the no-argument `supervise <name>` match.
- Screen-level: the pyte checks used by hand on 2026-11-05 (bar, separator,
  panel, resize, tty restore after q / Ctrl-C).

## Open decisions

- Signal for restart once HUP means "tty gone" (e.g. USR1 restart + suspend on
  another, or a command FIFO in `.run/`). Changes `svc`'s protocol, so old
  supervisors need restarting after the upgrade.
- `svc_cmd` string semantics (`bash -c` vs argv).
- Wrapper name: `svc-tmux` vs `svc up` (one CLI, but `svc` then starts things).
