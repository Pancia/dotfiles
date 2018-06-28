export CACHE_RM_MAX_HISTORY=500

export CACHE_RM_HISTORY="$HOME/.cache/dotfiles/rm/history"

function _record_rm {
    [ ! -d "$CACHE_RM_HISTORY" ] && mkdir -p "$(dirname $CACHE_RM_HISTORY)"
    printf '"%s" "%s"\n' "$f" "$dest" >> "$CACHE_RM_HISTORY"
    if [[ $CACHE_RM_MAX_HISTORY -lt $(wc -l "$CACHE_RM_HISTORY" | awk '{print $1}') ]]; then
        local tmp="$(mktemp)"
        awk -F"CACHE_SEP" '{if (NR != 1) { print $0 } }' "$CACHE_RM_HISTORY" > "$tmp"
        mv "$tmp" "$CACHE_RM_HISTORY"
    fi
}

function rm {
    local dir prefix timestamp failed
    dir="$(pwd)"
    timestamp="$(date '+%Y-%m-%d_%X')"
    prefix="${dir//\//%}"
    suffix="${timestamp}"
    failed=false
    for f in "$@"; do
        if [ -e "$f" ]; then
            local dest="${HOME}/.Trash/${prefix}>>>${f//\//%}<<<${suffix}"
            echo "[dotfiles/rm] moving '${f}' to '${dest}'"
            mv "${f}" "${dest}"
            _record_rm "$f" "$dest"
        else
            failed=true
            >&2 echo "[dotfiles/rm] file not found: '$f'"
        fi
    done
    $failed && return 1
}

function restore {
    case "$1" in
        '') command cat -n $CACHE_RM_HISTORY | awk '{print $3}' ;;
        *) echo "$@" ;;
    esac
}
