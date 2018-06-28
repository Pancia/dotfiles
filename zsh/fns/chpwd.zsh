function cache {
    local cache_root="$HOME/.cache/dot-cache"
    case "$1" in
        clear|purge) [ -d "$cache_root" ] && command rm -r "$cache_root" ;;
        *)
            local lock_file="$cache_root/`pwd`/$2.lock"
            local now=$(date +%s 2>/dev/null)
            local last=$(cat $lock_file 2>/dev/null || echo '0')
            local SEC_TO_MIN=60
            local delta=$(($now-$last))
            local interval=$(($1*$SEC_TO_MIN))
            if [ $delta -ge $interval ]; then
                (eval "${@:2}" &)
                mkdir -p "$(dirname $lock_file)" && echo "$now" > "$lock_file"
            fi
            ;;
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
    if [[ -e "~/TODL_$wifi_name" ]]; then
        echo "&> TODL:"
        cat "~/TODL_$wifi_name"
    fi
}

function chpwd {
    cache 15 showTodos
    cache 5 listVims
    cache 5 checkWifiTODL
}
