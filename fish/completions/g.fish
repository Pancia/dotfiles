# Completions for the `g` VCS menu dispatcher

complete -c g -f

function __g_run_keys
    command g ls 2>/dev/null | string replace -ra '\e\[[0-9;]*m' '' | while read -l line
        set -l parts (string match -r '^(..)\s\s+(.+?)\s\s+(.+)$' -- $line)
        test (count $parts) -ge 3; or continue
        set -l key (string trim -- $parts[2])
        set -l desc (string trim -- $parts[3])
        test -n "$key"; and printf '%s\t%s\n' $key $desc
    end
end

complete -c g -n '__fish_use_subcommand' -a run -d 'Execute a menu command by key'
complete -c g -n '__fish_use_subcommand' -a ls -d 'List all menu commands'
complete -c g -n '__fish_use_subcommand' -a help -d 'Show menu reference'

complete -c g -n '__fish_seen_subcommand_from run' -a '(__g_run_keys)'
