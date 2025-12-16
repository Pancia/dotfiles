# Completions for cmds command

# Get available subcommands
function __cmds_subcommands
    cmds --zsh-completions 2>/dev/null | string match -r '1:cmd:\(([^)]+)\)' | string replace '1:cmd:(' '' | string replace ')' '' | string split ' '
end

# Get existing function names from current cmds.rb
function __cmds_functions
    set -l cmds_file "$HOME/dotfiles/cmds/"(pwd)"/cmds.rb"
    if test -f "$cmds_file"
        grep -oE 'def [a-z_][a-z0-9_]*' "$cmds_file" 2>/dev/null | string replace 'def ' ''
    end
end

# Complete subcommands
complete -c cmds -f -n '__fish_use_subcommand' -a '(__cmds_subcommands)'

# Complete function names for edit subcommand
complete -c cmds -f -n '__fish_seen_subcommand_from edit' -a '(__cmds_functions)' -d 'existing function'

# Complete options
complete -c cmds -s h -l help -d 'Print help document'
complete -c cmds -s v -l verbose -d 'Print more, for debugging'
complete -c cmds -s n -l dry-run -d 'Dry run / simulation'
