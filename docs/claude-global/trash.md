# `trash` subcommands

`trash` is a subcommand CLI, usable from any shell (the `bin/trash` shim forwards to the Fish function):
- `trash <paths>` (or `trash put <paths>`) — move files to the trash
- `trash list [--json]` — list trashed files, newest first; `--json` emits one object per entry with a stable `id`, original `path`, and `present` flag
- `trash restore --last` — restore the most recently trashed file
- `trash restore <id>` — restore a specific entry by the `id` shown in `trash list` (`restore` is a top-level alias for `trash restore`)

To trash a file literally named `put`/`list`/`restore`/`help`, use `trash put <name>`.
