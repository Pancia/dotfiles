# Claude Code mods

Each folder here is a Claude Code mod: a plugin with a hooks module
(`hooks/register.tsx`) and its types (`types/index.d.ts`). `CLAUDE_CODE_PLUGIN_DIRS`
in `rcs/claude-settings.json` loads each one into every new interactive session.
This file sits outside every mod folder, so editing it reloads nothing.

| Mod | What it does | Docs |
|---|---|---|
| `plainify` | the `/plainify` command: rewrites the last reply shorter and plainer | `CLAUDE.md`, the `plainify` row |
| `roleplay-bookends` | Sonnet writes the roleplay opener and closer around each turn | [roleplay/docs/claude-roleplay.md](../../roleplay/docs/claude-roleplay.md) |
| `focus-verbose` | `/focus off` also turns verbose on | — |

## Editing a mod

- **Edit `ai/mods/<name>` directly.** A copy in `~/.claude/dev-mods/<session>/`
  matters only to the session that made the mod.
- **A save reaches every open session.** In the session that saved it, the mod
  reloads at the end of that turn. In every other open session it reloads about a
  quarter second after the last save, even in the middle of a turn. A reload runs
  `register` again in a fresh environment, so the module's memory is lost and any
  call in flight is cut off.
- **A bad save hits every session at once.** The plugin guide says a module that
  fails to load at a reload leaves the previous version loaded, but a hook that
  throws at run time unloads the mod. For a risky change, copy the folder to a
  scratch directory, test it there, then copy the result in.
- Files a mod does not import (tests, this README) reload nothing when saved.

## Checking a mod

```bash
claude plugin test ai/mods/<name>                     # the mod's tests/*.test.ts(x)
claude plugin validate ai/mods/<name>                 # manifest and hooks module
npx -y -p typescript@5.6.3 tsc -p ai/mods/<name>      # types; writes nothing (noEmit)
cmds test mods                                        # every mod that has tests/
```

- `claude plugin test` runs each test file in a child of the claude binary, with
  no fs, network or process access. The test's own hooks answer for the engine:
  `process.run`, `model.complete`, `session.id`, and `mock.clock` for timers.
  `ai/mods/roleplay-bookends/tests/flow.test.tsx` is a worked example.
- A test file that imports from `../hooks/register` gets its own copy of the
  module, not the one the engine loaded, and module state carries across the
  tests in one file. Test stateful code through the events instead.
- Only `*.test.ts(x)` files run, so a shared helper such as
  `roleplay-bookends/tests/world.tsx` is safe in `tests/`. Build its state
  inside the function: module state carries across the tests in a file.
- `tsc` is not on PATH. Bare `npx tsc` runs the unrelated `tsc` package, and an
  unpinned `-p typescript` installs whatever is newest, outside the pnpm
  release-age policy. Pin the version.
- `.claude-plugin/types/` is written by the engine when a session loads the mod,
  and git ignores it. A fresh clone has no types until a session has loaded the
  mod, so `tsc` fails there ("Cannot read file …/types/tsconfig.json").
  `claude plugin test` still works.
- `validate` warns that there is no icon. That matters only for a directory
  listing.
