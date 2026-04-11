# Commit Current Changes

Create a commit for the current working-copy changes. Auto-detects jj vs git.

## Style template (auto-loaded)

@~/dotfiles/ai/templates/git_commit_style.md

The style rules above are the source of truth for subject length,
imperative mood, body wrapping, and bullet style. (Same rules the
`ai_write_git_commit` Fish helper uses via `dotfiles_ai_git_commit.md`,
which wraps this same file with extra `<commit>`-tag output instructions.)

## Extra instructions

$ARGUMENTS

If the block above is non-empty, treat it as additional guidance from the
user for this specific commit (e.g. "squash into previous", "mark as WIP",
"scope to just the nvim changes", "use conventional commit prefix", etc.).
Honor those instructions over the defaults below when they conflict.

## Procedure

1. **Survey the changes** by running exactly this one command:

   ```
   vcs-status-for-ai
   ```

   It auto-detects jj vs git, and emits labeled sections: `### VCS`,
   `### STATUS`, `### DIFF_STAT`, `### CURRENT_COMMIT`, `### RECENT_COMMITS`.
   Use the VCS section to decide whether to use jj or git commands in step 4.
   Use the RECENT_COMMITS section to match the repo's existing commit style.

   The default output is **stat-only** (changed files + line counts). If you
   need to read the actual hunks to draft an accurate commit message — which
   is the common case — re-run with `vcs-status-for-ai --diff` to get the
   full diff body.

   Also check the project's `CLAUDE.md` for VCS-specific conventions (e.g.
   whether to advance a `master`/`main` bookmark after `jj commit`).

2. **Scope check.** Before drafting anything, look at the changed files from
   step 1 and decide whether they belong to a single logical change.

   - If everything is clearly one concern (e.g. all files touch the same
     feature, or the user's `$ARGUMENTS` block already specifies a scope),
     proceed to step 3.

   - If the working copy contains **multiple unrelated concerns** (e.g. a
     nvim keymap change alongside an unrelated Python script refactor),
     **stop and use the `AskUserQuestion` tool** to ask the user how to
     proceed. Offer these options:

     1. **Commit everything together** — one commit, one message covering
        all the changes
     2. **Commit only a subset** — user names which files/concerns to
        include; you'll use `jj split` (jj) or path-specific `git add`
        (git) to scope the commit
     3. **Abort** — do nothing, let the user sort it out manually

     In the question text, list the distinct concerns you detected so the
     user can see what triggered the prompt. Do not proceed to step 3 until
     the user answers. If `$ARGUMENTS` already gave explicit scoping
     instructions, skip this check — the user has already told you the
     scope.

3. **Draft the commit message** following the auto-loaded style template.

   Additionally:
   - Match the repo's existing tone where it diverges from the template
     (conventional commits prefix? emoji? check recent commits)
   - Do NOT include a `Co-Authored-By` trailer unless the repo already uses
     them in recent commits
   - Do NOT mention Claude / AI authorship unless the user asked for it

4. **Safety checks before committing**:
   - Never commit files that look like secrets (`.env`, `credentials.json`,
     private keys, etc.) — warn the user and stop if any are staged
   - Never `git add -A` / `git add .` — add specific paths
   - Never use `--no-verify` / `--no-gpg-sign` unless the user explicitly asked
   - Never amend an existing commit unless the user explicitly asked

5. **Create the commit**:
   - **jj**: `jj commit -m "<message>"` using a heredoc for multi-line messages.
     To scope the commit to a subset of the working copy, pass filesets as
     positional args: `jj commit <paths...> -m "<message>"`. See the "jj common
     cases" section below for split/squash/partial-commit patterns.
     If the repo uses a `master`/`main` bookmark that tracks `@-`, advance it:
     `jj bookmark set master -r @-` (check the project's CLAUDE.md for the
     bookmark workflow — some repos advance manually, some don't)
   - **git**: stage specific files by path, then `git commit -m "<message>"`
     via heredoc

6. **Verify**: run `jj st` or `git status` after the commit to confirm success.

7. **Do not push** unless the user explicitly asked.

## Heredoc format for multi-line messages

```
jj commit -m "$(cat <<'EOF'
Subject line here

Body paragraph explaining the why, wrapped to ~72 columns. Reference
the specific files or behaviors changed when it adds clarity.
EOF
)"
```

## jj common cases

> ⚠️ **Always pass `-m "<message>"`.** `jj commit`, `jj split`, `jj describe`,
> and friends will drop into `$EDITOR` interactively when no message is given,
> which **hangs the agent session** (no TTY to close the editor). Same goes for
> `-i` / `--interactive` — those launch a TUI diff picker and will hang. Stick
> to non-interactive invocations with explicit `-m` and explicit filesets.

`jj commit` without filesets acts on the entire working copy (`@`). To scope a
commit to specific files, pass filesets as positional arguments — the selected
paths stay in `@` and get committed, while the rest of the diff is moved to a
new working-copy change on top.

```
# Commit only the listed files; other changes stay in the new @
jj commit path/to/a.fish path/to/b.md -m "<message>"

# Same thing with a heredoc message
jj commit path/to/a.fish -m "$(cat <<'EOF'
Subject line

Body paragraph.
EOF
)"
```

Other useful patterns:

- **Drop a change out of an existing commit** (e.g. you committed too much, or
  a file belongs in a separate commit): `jj split -r <rev> <paths>` — moves
  `<paths>` into a new child and leaves the rest in `<rev>`. Use `-p` for
  parallel siblings instead of parent/child.
- **Move a file into the parent commit** (e.g. you noticed a fixup that belongs
  in `@-`): `jj squash <paths>` — default `--from @ --into @-`. Add
  `--into <rev>` to target a different ancestor.
- **Describe without creating a new change**: `jj describe -m "<message>"`
  updates the message on `@` in place. Prefer `jj commit` when you want to
  start a fresh empty change afterward.
- **Fileset syntax**: paths are fileset expressions, so globs and
  `~exclusions` work — e.g. `jj commit 'glob:bin/*.py' -m "..."` or
  `jj commit . ~'glob:**/*.lock' -m "..."`. Quote globs to keep the shell from
  expanding them.

## Notes

- If there are no changes, say so and stop — do not create an empty commit
- If a pre-commit hook fails, fix the underlying issue and create a NEW commit
  (never `--amend` to work around a failed hook — the original commit didn't
  happen, so amend would modify the *previous* commit and can destroy work)
- For jj repos: the working copy `@` is always a mutable change. `jj commit`
  describes `@` and creates a new empty change on top. There is no staging area.
