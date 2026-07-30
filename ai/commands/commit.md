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

## Concurrent sessions — check this first

In a jj repo, run `ccjj should-scope` before anything else. If it **exits 0**,
another live Claude session is working in this same working copy, and a plain
`jj commit` would capture its half-written files. Commit with:

```bash
commit-mine -m "<message>"
```

That replays only *this* session's recorded edits onto `@-`, leaving the other
session's work untouched and on disk. It splits a file both sessions edited, not
just disjoint files. Use `commit-mine --diff` to preview, and
`commit-mine -m "<msg>" --also <path>` for a delete or rename made with Bash.

Exit `4` means locked, the base moved, or the working copy is a merge — wait and
retry, it is not an error. Exit `1` is a refusal that re-running will reproduce;
read the message rather than retrying. Full details: `docs/cc-jj-sessions.md`.

`commit-mine` **stops with exit `5`** if this session has Bash-window changes
nobody has claimed, and names the exact `ccjj claim` commands. Claim the ones
that are yours and re-run, and it all lands in **one** commit. If some of them
are not yours (a build artifact, another program's rewrite), re-run with
`--no-claim` to commit without them. Same for `ai_jj_commit` / `g run ci`.

### Before committing, run `ccjj audit`

It lists working-copy paths no session claims. Changes you made through **Bash**
(`sed -i`, `>`, a heredoc, a script that rewrites a file) are invisible to the
Edit/Write hook, so they are unclaimed and `commit-mine` will silently leave them
behind. `audit` is what makes that loud.

If this checkout has Bash windows enabled, `audit` annotates the ones it can
recover:

```
    services/disk-snapshot/script.sh
        changed inside your Bash window (modified) -- recoverable:
        ccjj claim services/disk-snapshot/script.sh   # after reading the diff it prints
```

**You are the reader.** `ccjj claim` prints the diff and then records it — there
is no confirmation prompt, by design. So actually read the diff before deciding,
and claim only what you know you did:

- Recognise the change as yours → claim it, then commit.
- The diff contains anything you did not do — another session's edit, a config
  file rewritten by some other program, an unrelated build artifact → **do not
  claim it**. Say so in your report instead. A window is a snapshot difference,
  so it catches everything that happened in that interval, not only your work.
- `claim` refuses outright for symlinks, deletions, renames, a path another
  session has a stake in, and a path that appeared in `@-` meanwhile. Those
  refusals are not obstacles to work around — take the suggested route
  (`--also`) or leave the change uncommitted.

For a deletion or rename made with Bash, skip `claim` and use
`commit-mine -m "msg" --also <old> --also <new>`. `--also` takes a path
**wholesale** and is never byte-verified, so use it only for whole-path changes,
never for a content edit to a file someone else may be working on.

If `@- has moved` appears, something outside `ccjj` committed — `audit` names the
exact `jj op restore <id>` to undo it. Report that to the user before doing
anything else; do not run the restore unprompted, it rewinds the whole repo.

If `ccjj should-scope` exits non-zero (the usual case — you are the only session
here), ignore all of the above and follow the normal procedure below. A
whole-working-copy commit is *better* then, because it also captures changes made
via Bash.

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

     1. **Session only** — commit only the changes from this session,
        leaving unrelated changes in the working copy
     2. **Everything** — one commit covering all changes, one message
     3. **Pick** — user specifies which files/concerns to include;
        you'll use `jj split` (jj) or path-specific `git add` (git)
        to scope the commit
     4. **Abort** — do nothing, let the user sort it out manually

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

6. **Verify, and report what actually landed.** Two separate things — what went
   in, and what is left behind:

   ```
   # jj
   jj diff -r @- --stat      # files + line counts in the new commit
   jj status                 # what remains in the working copy

   # git
   git show HEAD --stat --format=
   git status
   ```

   Use `--summary` in place of `--stat` for a bare file list with no line
   counts (`jj diff -r @- --summary` / `git show HEAD --name-status --format=`).

   **Do not reach for `--no-patch`.** In jj it is rejected outright —
   `--no-patch` cannot be combined with `--summary` or `--stat` — and
   `jj show -r @- --summary` does work but replays the entire commit message
   before the file list, which is noise when the body is long. `jj diff -r @-`
   is the one that answers "which files landed" directly.

   Then **tell the user the file list**, not just "committed successfully".
   This matters most when step 2 scoped the commit to a subset: the useful
   report is which paths went in *and* which deliberately stayed behind, so a
   mis-scoped commit is visible immediately rather than at the next `jj status`.

7. **Do not push** unless the user explicitly asked. If the repo advances a
   `master`/`main` bookmark manually and you did not touch it, say so — a
   commit that is not on the bookmark will not be pushed, and silence reads as
   "done".

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
