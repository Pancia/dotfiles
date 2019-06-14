function vim_startuptime {
    local timestamp="$(date +%s%N)"
    local log_file="/tmp/vim-startup/$timestamp.log"
    mkdir -p $(dirname log_file)
    vim --startuptime "$log_file" "$@"
    export VIM_STARTUPTIME_LOG_FILE="$log_file"
    echo "$log_file => \$VIM_STARTUPTIME_LOG_FILE"
    echo "use debug_vim_startuptime to debug startuptime"
}

function debug_vim_startuptime {
    echo "$VIM_STARTUPTIME_LOG_FILE"
    local finish_time=$(grep 'NVIM STARTED' $VIM_STARTUPTIME_LOG_FILE)
    local head_sorted_log=$(sort -k2 -nr $VIM_STARTUPTIME_LOG_FILE | head -n 15)
    less -f <(echo "FINISH TIME:"; echo $finish_time; echo; \
              echo "SORTED BY TIME TAKEN:"; echo $head_sorted_log)
    less $VIM_STARTUPTIME_LOG_FILE
}
