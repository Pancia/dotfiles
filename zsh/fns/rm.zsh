function rm {
    local dir prefix timestamp failed
    dir="$(pwd)"
    timestamp="$(date '+%Y-%m-%d_%X')"
    prefix="${dir//\//%}"
    suffix="${timestamp}"
    failed=false
    for f in "$@"; do
        if [ -e $f ]; then
            local dest="${HOME}/.Trash/${prefix}>>>${f//\//%}<<<${suffix}"
            echo "moved ${f} to ${dest}"
            mv "${f}" "${dest}"
        else
            failed=true
            >&2 echo "[dotfiles/rm] file not found: $f"
        fi
    done
    $failed && return 1
}
