function debug_vim_startuptime --description 'Debug vim startup time'
    echo "$VIM_STARTUPTIME_LOG_FILE"
    set -l finish_time (grep 'NVIM STARTED' $VIM_STARTUPTIME_LOG_FILE)
    echo "FINISH TIME:"
    echo "$finish_time"
    echo
    echo "SORTED BY TIME TAKEN:"
    sort -k2 -nr $VIM_STARTUPTIME_LOG_FILE | head -n 15
    echo
    echo "Press enter to view full log..."
    read
    bat $VIM_STARTUPTIME_LOG_FILE
end
