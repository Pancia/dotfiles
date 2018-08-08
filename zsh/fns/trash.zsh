export TRASH_CACHE_MAX_HISTORY=500

export TRASH_CACHE_HISTORY="$HOME/.cache/dotfiles/trash/history"

function _record_trash {
    [ ! -d "$TRASH_CACHE_HISTORY" ] && mkdir -p "$(dirname $TRASH_CACHE_HISTORY)"
    printf '%s\t%s\n' "$f" "$dest" >> "$TRASH_CACHE_HISTORY"
    if [[ $TRASH_CACHE_MAX_HISTORY -lt $(wc -l "$TRASH_CACHE_HISTORY" | awk '{print $1}') ]]; then
        local tmp="$(mktemp)"
        awk -F'\t' '{if (NR != 1) { print $0 } }' "$TRASH_CACHE_HISTORY" > "$tmp"
        mv "$tmp" "$TRASH_CACHE_HISTORY"
    fi
}

function trash { # mv to ~/.Trash
    local dir prefix timestamp failed
    dir="$(pwd)"
    timestamp="$(date '+%Y-%m-%d_%X')"
    prefix="${dir//\//%}"
    suffix="${timestamp}"
    failed=false
    for f in "$@"; do
        if [ -e "$f" ]; then
            local dest="${HOME}/.Trash/${prefix}>>>${f//\//%}<<<${suffix}"
            echo "[dotfiles/trash] INFO: moving '${f}' to '${dest}'"
            mv "${f}" "${dest}"
            _record_trash "$f" "$dest"
        else
            failed=true
            >&2 echo "[dotfiles/trash] ERROR: file not found: '$f'"
        fi
    done
    $failed && return 1
}

function restore { # restore from ~/.Trash
    case "$1" in
        '') selected=$(mktemp)
            command cat -n $TRASH_CACHE_HISTORY | awk -F'\t' '{print $1"\t"$3}' | tail -r \
                | search --on-cancel error > $selected && restore $selected
            ;;
        *)
            line_num="$(cat $1 | cut -f1)"
            [ -z "$line_num" ] && >&2 echo "[ERROR][restore]: Must select a line" && return 1
            local line="$(awk "{ if (NR == $line_num) { print \$0 } }" $TRASH_CACHE_HISTORY)"
            local file="$(basename `echo $line | cut -f2` | sed -E 's/(>>>)|(<<<)/\\t/g')"
            local folder="$(echo $file | cut -f1 | sed 's/%/\//g')"
            local fname="$(echo $file | cut -f2 | sed 's/%/\//g')"
            local src="$(echo $line | cut -f2)"
            if [[ "$fname" =~ "^/" ]]; then
                local dest="$fname"
            else
                local dest="$folder/$fname"
            fi
            echo "[dotfiles/restore] INFO: moving $src -> $dest"
            mv "$src" "$dest" \
                && sed -i '' "${line_num}d" $TRASH_CACHE_HISTORY
            ;;
    esac
}

function rm { # rm but warn
    if [ -n $PS1 ]; then
        >&2 echo "[rm] WARNING: prefer \`trash\`"
    fi
    command rm "$@"
}
