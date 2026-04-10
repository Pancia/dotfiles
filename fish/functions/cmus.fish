function cmus --description 'Start cmus with random mode' --wraps cmus
    set -l ml $MUSIC_LIBRARY
    fish -c "
        sleep 1
        cmus-remote -C 'add $ml'
        while true
            cmus-remote -C player-play 2>/dev/null
            if cmus-remote -Q 2>/dev/null | string match -q 'status playing'
                break
            end
            sleep 3
        end
        cmus-remote -C player-stop
        cmus-remote -C rand
        cmus-remote -C win-top
        cmus-remote -C win-activate
    " &>/dev/null &
    disown
    env LC_ALL=C.UTF-8 command cmus $argv
end
