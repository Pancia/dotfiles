function rm {
    local dir prefix timestamp failed
    dir="$(pwd)"
    timestamp="$(date '+%Y-%m-%d_%X')"
    prefix="${dir//\//%}T${timestamp}<->"
    failed=false
    for f in "$@"; do
        if [ -e $f ]; then
            echo "moved ${f} to" ~/.Trash/${prefix}${f//\//%}
            mv ${f} ~/.Trash/${prefix}${f//\//%}
        else
            failed=true
            echo "[dotfiles/rm] file not found: $f" >&2
        fi
    done
    $failed && return 1
}
