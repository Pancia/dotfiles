# Completions for notes command

# Get available subcommands
function __notes_subcommands
    notes --zsh-completions 2>/dev/null | string match -r '1:cmd:\(([^)]+)\)' | string replace '1:cmd:(' '' | string replace ')' '' | string split ' '
end

# Complete subcommands
complete -c notes -f -n '__fish_use_subcommand' -a '(__notes_subcommands)'

# Complete options
complete -c notes -s h -l help -d 'Print help document'
