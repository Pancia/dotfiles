function music {
    ~/projects/cmus-mediakeys/mediakeys > /dev/null &; pid=$!
    cmus "$@"
    kill $pid
}
