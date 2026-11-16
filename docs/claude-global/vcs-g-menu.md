# VCS menu (`g`)

`g` is a which-key modal menu for git/jj that auto-detects the repo type. Use `g ls` to see all available commands.

**Non-interactive CLI** (for scripting and AI agents):
- `g ls` / `g help` — list all commands with key paths and shell commands
- `g run <keys>` — execute by key path (e.g. `g run cc`, `g run ci`, `g run s`)

**Jujutsu (jj) workflow:** In jj repos (`.jj/` directory), the working copy (`@`) is always a mutable change — no staging area. Key operations:
- `jj describe` — set/update the commit message on `@` (stays in same change)
- `jj commit` — describe `@` and create a new empty change on top (`describe` + `new`)
- `jj new` — create new empty change on top of `@`
- Advance + push — `jj commit` → `jj bookmark set master -r @-` → `jj git push`

AI-generated commit messages available via `g run ci` (`ai_jj_commit` / `ai_git_commit`).

**To commit, prefer `/cc:commit` or `g run ci` over a raw `jj commit`.** Both
detect the VCS themselves (via `vcs-status-for-ai`, which takes the *nearest*
marker walking up) and route to `commit-mine` when another live session shares
the working copy. Because they compute the answer instead of assuming it, they
stay correct in the exception below, where a hardcoded "use jj" does not.

**Exception — in a git worktree of a jj repo, use `git`.** Claude Code's
`--worktree` creates a *git* worktree with no `.jj` of its own, so `jj` there
walks up and resolves to the **parent** repo. Two ways that bites:

- `jj commit` commits the **parent's** working copy — very likely another
  session's in-flight work — while your own changes stay uncommitted.
- `jj st` / `jj log` report the **parent's** state, so your own edits look like
  they vanished. Do not "fix" that by redoing the work.

Tell by location: you are in one if the cwd is under `.claude/worktrees/<name>/`,
or if `.git` is a **file** rather than a directory. Use `git` for everything
there — it is a complete workflow, not a fallback: the commits come back to the
parent as a jj bookmark of the same name automatically, and the parent's working
copy is left untouched. `bin/cc-worktree-nudge` re-asserts this every prompt when
it detects the situation, and overrides any project CLAUDE.md that says
otherwise.

**VCS Hooks:** Repos can define `./vcs-hooks/post-commit` (executable) to run after commit-like operations through `g`.
