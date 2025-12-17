function cmus --description 'Start cmus with random mode' --wraps cmus
    fish -c "sleep 1; cmus-remote -C rand -C player-play" &>/dev/null &
    disown
    env LC_ALL=C.UTF-8 command cmus $argv
end
