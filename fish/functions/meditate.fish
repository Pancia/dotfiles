function meditate --description 'Meditation timer with cmus control'
    set -l minutes (test -n "$argv[1]"; and echo $argv[1]; or echo 5)
    set -l seconds (math "60 * $minutes")
    echo "sleeping for $seconds seconds"
    cmus-remote --stop
    sleep $seconds
    echo "wakeup!"
    cmus-remote --play
end
