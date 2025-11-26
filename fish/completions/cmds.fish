# Completions for cmds command

# Get available subcommands
function __cmds_subcommands
    cmds --zsh-completions 2>/dev/null | string match -r '1:cmd:\(([^)]+)\)' | string replace '1:cmd:(' '' | string replace ')' '' | string split ' '
end

# Complete subcommands
complete -c cmds -f -n '__fish_use_subcommand' -a '(__cmds_subcommands)'

# Complete options
complete -c cmds -s h -l help -d 'Print help document'
complete -c cmds -s v -l verbose -d 'Print more, for debugging'
complete -c cmds -s n -l dry-run -d 'Dry run / simulation'
