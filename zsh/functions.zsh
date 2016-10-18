function rm {
    local dir prefix timestamp
    dir="$(pwd)"
    timestamp="$(date '+%Y-%m-%d_%X')"
    prefix="${dir//\//%}T${timestamp}<->"
    for i in "$@"; do
        echo "moved ${i} to" ~/.Trash/${prefix}${i//\//%}
        mv ${i} ~/.Trash/${prefix}${i//\//%}
    done
}

function lrw {
    (echo "$@"; cat <&0) | lein repl
}
