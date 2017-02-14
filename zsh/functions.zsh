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
    while [ ! -f "$1" ]; do; sleep 1; done;
    echo -n "Done waiting for $1"; shift; echo ", executing: '$@'."
    "$@" #TODO aliases arent working
}

function _fancy-ctrl-z {
    if [[ $#BUFFER -eq 0 ]]; then
        if [[ "$(jobs | wc -l)" -gt 1 ]]; then
            BUFFER="jobs"
            zle accept-line
            zle -U "fg %"
            zle end-of-line
        else
            BUFFER="fg"
            zle accept-line
        fi
    else
        zle push-input
        zle clear-screen
    fi
}
zle -N _fancy-ctrl-z
bindkey '^Z' _fancy-ctrl-z
