# Completions for command registry system (q)

# Get list of registers dynamically
function __q_registers
    ruby ~/dotfiles/lib/ruby/q.rb show 2>/dev/null | string match -r '^\S+\s+->' | string replace -r '\s+->.*$' ''
end

# q - execute registered command
complete -c q -f -a '(__q_registers)' -d 'Execute registered command'

# q! - register command
complete -c q! -f -a '(__q_registers)' -d 'Register command'

# qe - edit register
complete -c qe -f -a '(__q_registers)' -d 'Edit registered command'

# q_ - delete register
complete -c q_ -f -a '(__q_registers)' -d 'Delete registered command'
