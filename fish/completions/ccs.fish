# Completions for ccs (Claude Code Sessions)

complete -c ccs -f

# Subcommands
complete -c ccs -n __fish_use_subcommand -a add -d 'Add a session'
complete -c ccs -n __fish_use_subcommand -a list -d 'List sessions'
complete -c ccs -n __fish_use_subcommand -a remove -d 'Remove a session'
complete -c ccs -n __fish_use_subcommand -a resume -d 'Pick and resume a session'
complete -c ccs -n __fish_use_subcommand -a help -d 'Show help'

# Session IDs with titles for remove
complete -c ccs -n '__fish_seen_subcommand_from remove' -a '(test -f .claude-sessions && while read -l line; set -l parts (string split \t -- $line); printf "%s\t%s\n" $parts[1] "$parts[2..-1]"; end < .claude-sessions)'
