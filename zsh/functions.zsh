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
    (echo "$@"; command cat <&0) | lein repl
}

function lrcw {
    (echo "$@"; command cat <&0) | lein do clean, repl
}

function wait-for {
    while [ ! -f "$1" ]; do; sleep 1; done; shift
    echo "Done waiting for $1, executing: '$@'."
    "$@"
}
