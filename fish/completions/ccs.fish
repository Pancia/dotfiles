# Completions for ccs (Claude Code Sessions)

complete -c ccs -f

# Subcommands
complete -c ccs -n __fish_use_subcommand -a add -d 'Add a session'
complete -c ccs -n __fish_use_subcommand -a list -d 'List sessions'
complete -c ccs -n __fish_use_subcommand -a rename -d 'Rename a session'
complete -c ccs -n __fish_use_subcommand -a autotitle -d 'Auto-generate title with Haiku'
complete -c ccs -n __fish_use_subcommand -a remove -d 'Remove a session'
complete -c ccs -n __fish_use_subcommand -a resume -d 'Pick and resume a session'
complete -c ccs -n __fish_use_subcommand -a backup -d 'Back up session transcripts'
complete -c ccs -n __fish_use_subcommand -a migrate -d 'Migrate .claude-sessions to .cc/'
complete -c ccs -n __fish_use_subcommand -a help -d 'Show help'

# Session IDs with titles for remove, rename, autotitle
complete -c ccs -n '__fish_seen_subcommand_from remove rename autotitle' -a '(test -f .cc/sessions.json && jq -r \'.[] | [.id, (.title + " — " + .ts)] | @tsv\' .cc/sessions.json 2>/dev/null)' --no-files
