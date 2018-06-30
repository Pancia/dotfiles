function _cache {
    local lock_file="$1"
    local interval="$2"
    local CMD="${@:3}"

    local now=$(date +%s 2>/dev/null)
    local last=$(cat "$lock_file" 2>/dev/null || echo '0')
    local SEC_TO_MIN=60
    local delta=$(($now-$last))
    local interval=$(($interval*$SEC_TO_MIN))
    if [ $delta -ge $interval ]; then
        (eval "$CMD" &)
        mkdir -p "$(dirname $lock_file)" && echo "$now" > "$lock_file"
    fi
}

function cache {
    local cache_root="$HOME/.cache/dotfiles/cache/"
    case "$1" in
        clear|purge) shift; [ -d "$cache_root" ] && command rm -r "$cache_root" ;;
        global) shift; _cache "$cache_root/$2.glock" "$@" ;;
        *) _cache "$cache_root/`pwd`/$2.lock" "$@" ;;
    esac
}

function showTodos {
    [[ -f TODO ]] && echo "&> TODOS:" && cat TODO
}
function listVims {
    local VIMS="$(vims list)"
    [[ -n "$VIMS" ]] &&
        echo "&> VIMS:" && echo "$VIMS"
}

function checkWifiTODL {
    local wifi_name="$(networksetup -getairportnetwork en1 | awk -F':' '{print $2}')"
    if [[ -e "~/TODL_${wifi_name}.wiki" ]]; then
        echo "&> TODL:"
        cat "~/TODL_${wifi_name}.wiki"
    fi
}

function chpwd {
    cache 15 showTodos
    cache 5 listVims
    cache global 5 checkWifiTODL
}
