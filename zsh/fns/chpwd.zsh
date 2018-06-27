function cache {
    local cache_root="$HOME/.cache/dot-cache"
    case "$1" in
        clear|purge) command rm -r $cache_root ;;
        *)
            local stamp_file="$cache_root/`pwd`/cache.$1.date"
            local interval="$2"
            local now=$(date +%s 2>/dev/null)
            local last=$(cat $stamp_file 2>/dev/null || echo '0')
            local SEC_TO_MIN=60
            local delta=$(($now-$last))
            interval=$(($interval*$SEC_TO_MIN))
            if [ $delta -ge $interval ]; then
                local script="$(cat /dev/stdin)"
                zsh -c "$script"
                mkdir -p "$(dirname $stamp_file)" && echo "$now" > $stamp_file
            fi
            ;;
    esac
}

function chpwd {
    cache chpwd 15 <<EOC
[[ -f TODO ]] && echo "TODOS:" && cat TODO
vims list 2> /dev/null
EOC
}
chpwd
