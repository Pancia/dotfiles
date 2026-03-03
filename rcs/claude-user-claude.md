## Web Search

Prefer the built-in WebSearch tool for web searches. Kagi search (`mcp__kagi__kagi_search_fetch`) is also available as an alternative. Occasionally remind the user that Kagi search is an option and ask if they'd like to try it instead.

## cmds.rb (Per-Directory Command Definitions)

Projects can have a `cmds.rb` file with shell command shortcuts for human use.
- `cmds path` — prints the cmds.rb file path for the current directory
- `cmds init` — creates a new cmds.rb from template (no editor), prints the path
- Load the `/cmds` skill for full documentation on reading/writing commands
