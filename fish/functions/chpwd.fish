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

# The most any one of the lists below prints before "... N more"
set -g __chpwd_list_max 5

function _printCapped --description 'Print a list up to the limit, then how many were left out'
    set -l total (count $argv)
    test $total -gt 0; or return
    if test $total -le $__chpwd_list_max
        printf '%s\n' $argv
        return
    end
    printf '%s\n' $argv[1..$__chpwd_list_max]
    echo (set_color brblack)"  ... "(math $total - $__chpwd_list_max)" more"(set_color normal)
end

function _newestFiles --description 'Print paths, most recently modified first'
    test (count $argv) -gt 0; or return
    # -d: a directory named PLAN-* is one entry, not a listing of its contents
    command ls -td -- $argv
end

function _newestRows --description 'Sort ccs list rows by their last timestamp, newest first'
    for row in $argv
        set -l stamp (string replace -rf '.*(\d{4}-\d{2}-\d{2} \d{2}:\d{2}).*' '$1' -- $row)
        printf '%s\t%s\n' "$stamp" "$row"
    end | command sort -rs -t \t -k1,1 | command cut -f2-
end

function showTryOutReminder --description 'Tools worth remembering to try'
    echo "Remember to try out:"
    echo "scooter (find&replace), yazi(tui file manager), lazygit"
    echo "music ai_import, ii(ai_inbox), ..."
end

function showTodos --description 'Show TODO files if present'
    string match -q '*/dotfiles*' (pwd); and return
    if test -f TODO.wiki
        echo "&> TODO.wiki:"
        _printCapped (cat TODO.wiki)
    end
    if test -f wiki/TODO.wiki
        echo "&> wiki/TODO.wiki:"
        _printCapped (cat wiki/TODO.wiki)
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
        _printCapped $VIMS
    end
end

function listClaudeSessions --description 'List Claude sessions if present'
    set -l lines (ccs list)
    test -n "$lines"; or return
    echo "&> Claude sessions:"
    # ccs prints sections separated by blank lines, each a header and its rows.
    # The trailing '' closes the last section. Capped per section so a long
    # Open list cannot push Saved off the end.
    set -l section
    for line in $lines ''
        if test -n "$line"
            set -a section $line
        else if test (count $section) -gt 0
            printf '%s\n' $section[1]
            _printCapped (_newestRows $section[2..-1])
            set section
        end
    end
end

function showPendingUpdates --description 'Show pending CLAUDE.md update suggestions'
    set -l files (find .cc -maxdepth 1 -name 'pending-updates-*.md' 2>/dev/null)
    set -l count (count $files)
    if test $count -gt 0
        echo (set_color --bold d7871f)"&> $count pending CLAUDE.md update"(test $count -gt 1; and echo "s"; or echo "")" in .cc/"(set_color normal)
    end
end

function showPlans --description 'List PLAN-* files in .cc directory'
    set -l plans (find .cc -maxdepth 1 -name 'PLAN-*' 2>/dev/null)
    if test -n "$plans"
        echo "&> Plans:"
        _printCapped "  "(_newestFiles $plans)
    end
end

function showFixmes --description 'List FIXME* files in .cc directory'
    set -l fixmes (find .cc -maxdepth 1 -name 'FIXME*' 2>/dev/null)
    if test -n "$fixmes"
        echo (set_color --bold d75f5f)"&> FIXMEs:"(set_color normal)
        _printCapped "  "(_newestFiles $fixmes)
    end
end

function _recordCWD --description 'Record current working directory'
    set -l hist ~/.config/dir_history
    echo (pwd) >>$hist
    # `echo (cat $hist | sort | uniq) > $hist` collapsed the whole file onto one
    # space-separated line — command substitution splits on newlines and `echo`
    # rejoins the list with spaces. That left `z` reading a single 53KB "entry".
    # `sort -o` may name one of its own inputs; it reads them fully first.
    sort -u -o $hist $hist
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
    # One builtin append into this pane's journal; guarded because
    # revive-journal.fish is sourced separately (see config.fish)
    functions -q reviveRecordCwd; and reviveRecordCwd
    cache 15 showTodos
    cache 15 showCmds
    cache 5 listVims
    cache 5 listClaudeSessions
    cache 5 showPlans
    cache 5 showFixmes
    cache 5 showPendingUpdates
end

# Show plans on shell startup (this file is sourced from config.fish)
if status is-interactive; and isatty stdout
    showPlans
    showFixmes
end
