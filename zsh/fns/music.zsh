function mpl {
    ~/projects/cmus-mediakeys/mediakeys > /dev/null &; mdk_pid=$!
    cmus "$@"
    kill $mdk_pid
}
