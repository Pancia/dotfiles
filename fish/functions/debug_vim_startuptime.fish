function debug_vim_startuptime --description 'Debug vim startup time'
    echo "$VIM_STARTUPTIME_LOG_FILE"
    set -l finish_time (grep 'NVIM STARTED' $VIM_STARTUPTIME_LOG_FILE)
    set -l head_sorted_log (sort -k2 -nr $VIM_STARTUPTIME_LOG_FILE | head -n 15)
    less -f (echo "FINISH TIME:"; echo $finish_time; echo; \
             echo "SORTED BY TIME TAKEN:"; echo $head_sorted_log | psub)
    less $VIM_STARTUPTIME_LOG_FILE
end
