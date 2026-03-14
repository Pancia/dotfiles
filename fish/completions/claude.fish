# Completions for claude (Claude Code CLI)

# Subcommands
complete -c claude -n __fish_use_subcommand -a agents -d "List configured agents"
complete -c claude -n __fish_use_subcommand -a auth -d "Manage authentication"
complete -c claude -n __fish_use_subcommand -a auto-mode -d "Inspect auto mode classifier configuration"
complete -c claude -n __fish_use_subcommand -a doctor -d "Check auto-updater health"
complete -c claude -n __fish_use_subcommand -a install -d "Install Claude Code native build"
complete -c claude -n __fish_use_subcommand -a mcp -d "Configure and manage MCP servers"
complete -c claude -n __fish_use_subcommand -a plugin -d "Manage plugins"
complete -c claude -n __fish_use_subcommand -a plugins -d "Manage plugins"
complete -c claude -n __fish_use_subcommand -a setup-token -d "Set up authentication token"
complete -c claude -n __fish_use_subcommand -a update -d "Check for updates"
complete -c claude -n __fish_use_subcommand -a upgrade -d "Check for updates"

# Options
complete -c claude -l add-dir -d "Additional directories to allow tool access to" -rF
complete -c claude -l agent -d "Agent for the current session" -r
complete -c claude -l agents -d "JSON object defining custom agents" -r
complete -c claude -l allow-dangerously-skip-permissions -d "Enable bypassing permission checks as an option"
complete -c claude -l allowedTools -l allowed-tools -d "Tool names to allow" -r
complete -c claude -l append-system-prompt -d "Append to default system prompt" -r
complete -c claude -l betas -d "Beta headers for API requests" -r
complete -c claude -l brief -d "Enable SendUserMessage tool"
complete -c claude -l chrome -d "Enable Chrome integration"
complete -c claude -s c -l continue -d "Continue most recent conversation"
complete -c claude -l dangerously-skip-permissions -d "Bypass all permission checks"
complete -c claude -s d -l debug -d "Enable debug mode" -r
complete -c claude -l debug-file -d "Write debug logs to file" -rF
complete -c claude -l disable-slash-commands -d "Disable all skills"
complete -c claude -l disallowedTools -l disallowed-tools -d "Tool names to deny" -r
complete -c claude -l effort -d "Effort level" -ra "low medium high max"
complete -c claude -l fallback-model -d "Fallback model when overloaded" -r
complete -c claude -l file -d "File resources to download (file_id:path)" -r
complete -c claude -l fork-session -d "Create new session ID when resuming"
complete -c claude -l from-pr -d "Resume session linked to a PR" -r
complete -c claude -s h -l help -d "Display help"
complete -c claude -l ide -d "Connect to IDE on startup"
complete -c claude -l include-partial-messages -d "Include partial message chunks"
complete -c claude -l input-format -d "Input format" -ra "text stream-json"
complete -c claude -l json-schema -d "JSON Schema for structured output" -r
complete -c claude -l max-budget-usd -d "Maximum dollar amount for API calls" -r
complete -c claude -l mcp-config -d "Load MCP servers from JSON" -rF
complete -c claude -l mcp-debug -d "Enable MCP debug mode (deprecated)"
complete -c claude -l model -d "Model for the session" -ra "sonnet opus haiku"
complete -c claude -l no-chrome -d "Disable Chrome integration"
complete -c claude -l no-session-persistence -d "Disable session persistence"
complete -c claude -l output-format -d "Output format" -ra "text json stream-json"
complete -c claude -l permission-mode -d "Permission mode" -ra "acceptEdits bypassPermissions default dontAsk plan auto"
complete -c claude -l plugin-dir -d "Load plugins from directories" -rF
complete -c claude -s p -l print -d "Print response and exit"
complete -c claude -l replay-user-messages -d "Re-emit user messages on stdout"
complete -c claude -s r -l resume -d "Resume conversation by session ID" -r
complete -c claude -l session-id -d "Use specific session ID" -r
complete -c claude -l setting-sources -d "Setting sources to load" -r
complete -c claude -l settings -d "Path to settings JSON" -rF
complete -c claude -l strict-mcp-config -d "Only use MCP servers from --mcp-config"
complete -c claude -l system-prompt -d "System prompt for the session" -r
complete -c claude -l tmux -d "Create tmux session for worktree"
complete -c claude -l tools -d "List of available tools" -r
complete -c claude -l verbose -d "Override verbose mode setting"
complete -c claude -s v -l version -d "Output version number"
complete -c claude -s w -l worktree -d "Create new git worktree" -r
