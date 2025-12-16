# Directory change hooks and helpers
function _cache --description 'Cache command execution with time interval'
    set -l lock_file $argv[1]
    set -l interval $argv[2]
    set -l CMD $argv[3..-1]

    set -l now (date +%s 2>/dev/null)
    set -l last (cat "$lock_file" 2>/dev/null; or echo '0')
    set -l SEC_TO_MIN 60
    set -l delta (math "$now - $last")
    set -l interval_sec (math "$interval * $SEC_TO_MIN")

    if test $delta -ge $interval_sec
        eval "$CMD" &
        mkdir -p (dirname "$lock_file"); and echo "$now" > "$lock_file"
    end
end

function cache --description 'Manage cached command execution'
    set -l cache_root "$HOME/.cache/dotfiles/cache/"
    switch "$argv[1]"
        case help -h --help
            echo "cache [clear|purge|global] [CACHE_NAME]"
        case clear purge
            test -d "$cache_root"; and command rm -r "$cache_root"
        case global
            _cache "$cache_root/$argv[2].glock" $argv[3..-1]
        case '*'
            _cache "$cache_root"(pwd)"/$argv[2].lock" $argv
    end
end

function showTodos --description 'Show TODO files if present'
    string match -q '*/dotfiles*' (pwd); and return
    if test -f TODO.wiki
        echo "&> TODO.wiki:"
        cat TODO.wiki
    end
    if test -f wiki/TODO.wiki
        echo "&> wiki/TODO.wiki:"
        cat wiki/TODO.wiki
    end
end

function showCmds --description 'Show available cmds'
    set -l CMDS (cmds list)
    if test -n "$CMDS"
        echo "Available CMDS: $CMDS"
    end
end

function listVims --description 'List available vim sessions'
    set -l VIMS (vims list)
    if test -n "$VIMS"
        echo "&> VIMS:"
        echo "$VIMS"
    end
end

function showPlans --description 'List PLAN-* files in dotfiles directory'
    string match -q '*/dotfiles' (pwd); or return
    set -l plans (ls PLAN-* 2>/dev/null)
    if test -n "$plans"
        echo "&> Plans:"
        for plan in $plans
            echo "  $plan"
        end
    end
end

function _recordCWD --description 'Record current working directory'
    echo (pwd) >> ~/.config/dir_history
    echo (cat ~/.config/dir_history | sort | uniq) > ~/.config/dir_history
end

function recordCWD --description 'Record CWD if at git root or not in git'
    set -l root (git rev-parse --show-toplevel 2> /dev/null)
    if test -n "$root"
        if test (pwd) = "$root"
            _recordCWD
        end
    else
        _recordCWD
    end
end

# This hook is called on directory change (integrated into config.fish)
function chpwd_hook --on-variable PWD
    recordCWD
    cache 15 showTodos
    cache 15 showCmds
    cache 5 listVims
    showPlans
end

# Show plans on shell startup (this file is sourced from config.fish)
if status is-interactive; and isatty stdout
    showPlans
end
