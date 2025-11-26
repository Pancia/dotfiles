# Completions for service command

# Get available services from the services directory
function __service_list_services
    set -l services_dir ~/dotfiles/services
    if test -d $services_dir
        for dir in $services_dir/*/
            basename $dir
        end
    end
end

# Check if we're at the position for a service name argument
function __service_needs_service_name
    set -l cmd (commandline -opc)
    set -l subcmd $cmd[2]

    # Commands that need a service name as the next argument
    if contains -- $subcmd start stop restart log edit
        # Check if service name hasn't been provided yet
        if test (count $cmd) -eq 2
            return 0
        end
    end
    return 1
end

# Main subcommands
complete -c service -f -n '__fish_use_subcommand' -a 'list' -d 'List my services'
complete -c service -f -n '__fish_use_subcommand' -a 'start' -d 'Start a service'
complete -c service -f -n '__fish_use_subcommand' -a 'stop' -d 'Stop a service'
complete -c service -f -n '__fish_use_subcommand' -a 'restart' -d 'Restart a service'
complete -c service -f -n '__fish_use_subcommand' -a 'status' -d 'Status of all services'
complete -c service -f -n '__fish_use_subcommand' -a 'log' -d 'Show the logs for a service'
complete -c service -f -n '__fish_use_subcommand' -a 'create' -d 'Create a new service'
complete -c service -f -n '__fish_use_subcommand' -a 'edit' -d "Edit a service's script and plist"

# Service name completions for commands that need them
complete -c service -f -n '__service_needs_service_name' -a '(__service_list_services)'

# Flags for restart command
complete -c service -f -n '__fish_seen_subcommand_from restart' -s l -l log -d 'Open log after restart'

# Completions for 's' alias (wraps service command)
complete -c s -w service
