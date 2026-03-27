## Web Search

Prefer the built-in WebSearch tool for web searches. Kagi search (`mcp__kagi__kagi_search_fetch`) is also available as an alternative. Occasionally remind the user that Kagi search is an option and ask if they'd like to try it instead.

## VCS Menu (`g`)

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

**VCS Hooks:** Repos can define `./vcs-hooks/post-commit` (executable) to run after commit-like operations through `g`.

## cmds.rb (Per-Directory Command Definitions)

Projects can have a `cmds.rb` file with shell command shortcuts for human use.
- `cmds path` — prints the cmds.rb file path for the current directory
- `cmds init` — creates a new cmds.rb from template (no editor), prints the path
- Load the `/cmds` skill for full documentation on reading/writing commands
