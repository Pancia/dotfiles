# work-config vault — private per-project config

This repo is **public**, so per-project config that must stay private lives in a
separate vault, **`~/Vaults/work-config`**, in a tree keyed by absolute path —
the private twin of `cmds/`:

```
~/Vaults/work-config/fs-config/<absolute project path>/cmds.rb    # cmds definitions
~/Vaults/work-config/fs-config/<absolute project path>/svc.conf   # supervise / svc / svc-tmux
```

- **`cmds`** searches `~/dotfiles/cmds`, then the vault, then the legacy
  `~/private/cmds` (logical path, then physical). `cmds init` writes to the vault
  for anything under `~/projects/work/`, to `cmds/` otherwise — and refuses if the
  vault isn't a git repo, so a `mkdir -p` can't block restoring it.
- **`supervise` / `svc` / `svc-tmux`** source `.svc.conf`, then the vault's
  `svc.conf`, then `.svc.local.conf` (`lib/svc/conf.sh`).
- Public projects' `cmds.rb` stay here in `cmds/`.

**Edits there are only backed up when committed in the vault.** It is a plain git
repo with no remote; the backup is a `post-commit` hook. So after creating or
editing *anything* in `~/Vaults/work-config` (a `cmds init`, a `svc.conf` tweak),
**commit in the vault** — `git -C ~/Vaults/work-config add -A && git -C ~/Vaults/work-config commit -m "..."`
— and check the hook printed `post-commit: backup OK`. An uncommitted edit exists
only on this disk. Ways to commit there:

- `git add -A && git commit` — the reliable one.
- `/cc:commit` — fine: it detects plain git and stages paths itself.
- **Not `g run ci`**: in a git repo it commits only *staged* changes, so a fresh
  `cmds init` file (untracked) is left out and nothing is backed up. `g run cI`
  stages everything first.
- Not `jj`: jj never runs git hooks.

## How the backup works, and its traps

- `.githooks/post-commit` writes `git bundle create --all` to
  `ProtonDrive…/git-bundles/work-config.bundle` via a temp file, `git bundle
  verify`s it, then swaps it in, so a failed write never replaces the last good
  bundle. It never `mkdir -p`s the ProtonDrive path (an unmounted drive would
  "succeed" into a local folder) and prints a red `BACKUP FAILED/SKIPPED` — a
  failing post-commit hook does **not** fail the commit. A lock held by another
  run is reported as such; a lock older than an hour is cleared.
- It fires on **commits only** — not `rebase`, `reset` or a fast-forward merge.
  After those, run `sh .githooks/post-commit` in the vault by hand.
- It runs only because the vault sets `core.hooksPath=.githooks`: the global
  `core.hooksPath` (`~/.config/git/config` → `~/dotfiles/git/hooks`) would
  otherwise win, and a `.git/hooks/post-commit` would silently never fire.
- The global gitignore's `.*` matches `.githooks/`, so **every** path in it is
  ignored: a new file there needs `git add -f`, and even `git add .githooks/post-commit`
  on the tracked hook exits with an error. `git add -A` is unaffected.
- Restore (README in the vault): `git clone <bundle>`, then
  `git config core.hooksPath .githooks` and `git remote remove origin` — neither
  the setting nor a sane remote survives a clone.
- Same ProtonDrive account as the AKR bundle: protection against disk loss, not
  account loss.
