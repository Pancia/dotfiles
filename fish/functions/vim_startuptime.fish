function vim_startuptime --description 'Profile vim startup time'
    set -l timestamp (date +%s%N)
    set -l log_file "/tmp/vim-startup/$timestamp.log"
    mkdir -p (dirname $log_file)
    vim --startuptime "$log_file" $argv
    set -gx VIM_STARTUPTIME_LOG_FILE "$log_file"
    echo "$log_file => \$VIM_STARTUPTIME_LOG_FILE"
    echo "use debug_vim_startuptime to debug startuptime"
end
