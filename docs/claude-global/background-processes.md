# `service` and `svc` details

### `service` — persistent launchd agents

Ruby CLI managing my `org.pancia.*` agents: **inari** (and all six Telegram
bots), sanctuary, hermes, lakshmi, copyparty, syncthing, vpc, tv-board, ziplog,
bookmark-manager, youtube-transcribe, wget_server, music-backup, disk-snapshot.
Names work short or full — `inari` == `org.pancia.inari`.

```
service status                          # table: SERVICE / PID / STATUS / LAST START / AGO
service start|stop <name>
service restart <name> [--log]
service log <name> -q -p [--lines N]    # agent-friendly: bounded snapshot, noise stripped
service log <name> --grep 'Error|Traceback|Exception' -p
```

`service log` auto-detects a non-TTY and prints a bounded snapshot instead of
hanging in `less +GF`; `-q` strips known polling noise — **only successful**
Telegram `getUpdates` responses, so failed polls (502 / 429 / 409, and the
"terminated by other getUpdates request" duplicate-instance alarm) still show.
Unlike `svc`, **starting is allowed** here — launchd owns these, not my terminal.
(`svc` services are started with `svc-tmux up`, below.)

Full docs: `~/dotfiles/wiki/pages/service.md`

### `supervise` / `svc` — ephemeral terminal-owned dev processes

`supervise` and `svc` run long-lived dev
processes in a terminal pane while an LLM can **restart** them on demand. I start
one with `supervise <name>` (usually a `cmds` entry); an LLM uses
`svc status|logs|restart|suspend|resume|stop <name>` to inspect/control it.

**To start one, an LLM uses `svc-tmux up --wait <name>`** — never `supervise`
directly (it would belong to the LLM's shell and die with it). That runs it in a
dedicated tmux server I can `svc-tmux attach` to, and exits nonzero with the
pane's last lines if it fails to come up. It needs `svc_cmd` in the project's
config; without one, ask me. Stop only what you started (`svc-tmux down <name>`).
If `svc` reports "not running", also check whether it's a `service` after all.
Per-project services are declared in `.svc.conf` / `.svc.local.conf`
(`SVC_SERVICES`, `svc_port_file`, optional `svc_eval`, `svc_cmd`, `SVC_ENV`).

Full docs (read if you need the config format, restart/crash semantics, or to add
it to a project): `~/dotfiles/wiki/pages/supervise-svc.md`
