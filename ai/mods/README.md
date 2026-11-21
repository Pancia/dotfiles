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
| `reply-links` | in the fullscreen terminal, an answer line under a question (`【Q4: yes* \| no】`, taught by the mod's own system-prompt section) is drawn as buttons, Where-next IDs as filled buttons (`[ N1 ]`), and question labels become links; a click fills the prompt box; a `[ submit ↵ ]` button at the end of every reply block (the mod draws them all) sends the box as your message; a slash command the session knows (`/cc:retro`) gets a button in a row under its paragraph, which puts it in an empty box, for Enter to run | comments in `hooks/linkify.ts` |

## Editing a mod

- **Edit `ai/mods/<name>` directly.** A copy in `~/.claude/dev-mods/<session>/`
  matters only to the session that made the mod.
- **A new mod, in the session that writes it.** That session read
  `CLAUDE_CODE_PLUGIN_DIRS` at its start, so it cannot load the new folder from
  there. Create the mod in `ai/mods/<name>`, then link it into the session's mods
  folder: `ln -s ~/dotfiles/ai/mods/<name> ~/.claude/dev-mods/<session-id>/<name>`.
  - Edit only by the `ai/mods` path. A path through the link is outside the repo,
    so `commit-mine` cannot record it.
  - Add the mod to `CLAUDE_CODE_PLUGIN_DIRS` last, when it works. Until then no
    other session loads it, so a half-done save reaches only this session.
  - Then remove the link.
  - The link is documented (the plugin guide: "A plugin folder given as a link is
    watched at the folder the link names") but not yet checked live. To check it:
    make a throwaway mod whose `register` raises a `$.ui.toast` with a version
    string, link it in, and confirm the toast. Edit the target by its real path
    and confirm the new string at the end of the turn. If nothing reloads, write
    in the dev-mods folder and copy the result into `ai/mods` once, before the
    commit.
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

## Drawing

- **Two mods on one component.** To redraw a component another mod may wrap,
  call `next(e)` first. Replace the single `{ type: 'engine' }` node in the tree
  it returns, and keep the rest of that tree (see `swapEngine` in
  `reply-links/hooks/register.tsx`). With zero or several engine nodes, return
  the tree as it came. Do not judge from `next.trace` outcomes: a hooks-module
  hook always reads `returned`. Draw from the props in the engine trace entry's
  `received`, not from `e.props`, or a rewrite by a mod beneath is lost.
- **Button hover.** A Button shows the pointer by setting `inverse` on its label.
  A label already drawn `inverse` shows no change, and a `hover` override cannot
  undo it. Fill a button with `backgroundColor` and `color` instead (checked
  2026-11-17).

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
