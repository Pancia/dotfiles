export TRASH_CACHE_MAX_HISTORY=500

export TRASH_CACHE_HISTORY="$HOME/.cache/dotfiles/trash/history"

function _record_trash {
    [ ! -d "$TRASH_CACHE_HISTORY" ] && mkdir -p "$(dirname $TRASH_CACHE_HISTORY)"
    printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" >> "$TRASH_CACHE_HISTORY"
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
            _record_trash "$f" "$prefix" "$suffix" "$dest"
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
            command cat -n $TRASH_CACHE_HISTORY | tail -r \
                | search --on-cancel error > $selected && restore $selected
            ;;
        *) line_num="$(cat $1 | cut -f1)"
            [ -z "$line_num" ] && >&2 echo "[ERROR][restore]: Must select a line" && return 1
            local line="$(awk "{ if (NR == $line_num) { print \$0 } }" $TRASH_CACHE_HISTORY)"
            local src="$(echo "$line" | cut -f4)"

            # Extract the filename from the trash path
            local trash_basename="$(basename "$src")"

            # Parse the encoded filename: prefix>>>filename<<<timestamp
            local prefix_encoded="$(echo "$trash_basename" | sed 's/>>>.*//')"
            local fname_encoded="$(echo "$trash_basename" | sed 's/.*>>>//; s/<<<.*//')"

            # Decode the prefix (folder) and filename
            local folder="$(echo "$prefix_encoded" | sed 's/%/\//g')"
            local fname="$(echo "$fname_encoded" | sed 's/%/\//g')"

            # Construct destination path
            if [[ "$fname" =~ ^/ ]]; then
                local dest="$fname"
            else
                local dest="$folder/$fname"
            fi

            echo "[dotfiles/restore] INFO: moving $src -> $dest"

            # Create destination directory if it doesn't exist
            mkdir -p "$(dirname "$dest")"

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
