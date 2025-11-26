# Completions for music command

# Get available subcommands
function __music_subcommands
    music --zsh-completions 2>/dev/null | string match -r '1:cmd:\(([^)]+)\)' | string replace '1:cmd:(' '' | string replace ')' '' | string split ' '
end

# Complete subcommands
complete -c music -f -n '__fish_use_subcommand' -a '(__music_subcommands)'

# Complete options
complete -c music -s h -l help -d 'Print help document'
complete -c music -s v -l verbose -d 'Print more, for debugging'
complete -c music -s n -l dry-run -d 'Dry run / simulation'
