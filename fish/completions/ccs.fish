# Completions for ccs (Claude Code Sessions)

complete -c ccs -f

# Subcommands
complete -c ccs -n __fish_use_subcommand -a add -d 'Add a session'
complete -c ccs -n __fish_use_subcommand -a list -d 'List sessions'
complete -c ccs -n __fish_use_subcommand -a rename -d 'Rename a session'
complete -c ccs -n __fish_use_subcommand -a autotitle -d 'Auto-generate title with Haiku'
complete -c ccs -n __fish_use_subcommand -a remove -d 'Remove a session'
complete -c ccs -n __fish_use_subcommand -a resume -d 'Pick and resume a session'
complete -c ccs -n __fish_use_subcommand -a old -d 'List archived sessions'
complete -c ccs -n __fish_use_subcommand -a prune -d 'Archive unrecoverable crashed entries'
complete -c ccs -n __fish_use_subcommand -a backup -d 'Back up session transcripts'
complete -c ccs -n __fish_use_subcommand -a migrate -d 'Migrate old sessions to ~/Cloud/cc-sessions/'
complete -c ccs -n __fish_use_subcommand -a help -d 'Show help'

complete -c ccs -n '__fish_seen_subcommand_from prune' -l dry-run -d 'Report what would be archived'
complete -c ccs -n '__fish_seen_subcommand_from prune' -s n -d 'Report what would be archived'

# Session IDs with titles for remove, rename, autotitle — saved sessions, plus
# crashed/running ones from the open registry (which is where a crashed
# session's title is recorded).
complete -c ccs -n '__fish_seen_subcommand_from remove rename autotitle' -a '(set -l f "$HOME/Cloud/cc-sessions"(pwd)"/sessions.json"; test -f "$f" && jq -r \'.[] | [.id, (.title + " — " + .ts)] | @tsv\' "$f" 2>/dev/null)' --no-files
complete -c ccs -n '__fish_seen_subcommand_from rename autotitle' -a '(ccs-entries 2>/dev/null)' --no-files
