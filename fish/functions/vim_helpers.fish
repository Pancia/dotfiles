# Vim helper functions
function vim --description 'Start nvim with socket' --wraps nvim
    if test -e .nvim.listen
        set -l socket (cat .nvim.listen)
    else
        set -l socket "/tmp/"(basename (pwd))".socket"
    end
    env TERM_TYPE=nvim nvim --listen $socket $argv
end

function vim_startuptime --description 'Profile vim startup time'
    set -l timestamp (date +%s%N)
    set -l log_file "/tmp/vim-startup/$timestamp.log"
    mkdir -p (dirname $log_file)
    vim --startuptime "$log_file" $argv
    set -gx VIM_STARTUPTIME_LOG_FILE "$log_file"
    echo "$log_file => \$VIM_STARTUPTIME_LOG_FILE"
    echo "use debug_vim_startuptime to debug startuptime"
end

function debug_vim_startuptime --description 'Debug vim startup time'
    echo "$VIM_STARTUPTIME_LOG_FILE"
    set -l finish_time (grep 'NVIM STARTED' $VIM_STARTUPTIME_LOG_FILE)
    set -l head_sorted_log (sort -k2 -nr $VIM_STARTUPTIME_LOG_FILE | head -n 15)
    less -f (echo "FINISH TIME:"; echo $finish_time; echo; \
             echo "SORTED BY TIME TAKEN:"; echo $head_sorted_log | psub)
    less $VIM_STARTUPTIME_LOG_FILE
end
