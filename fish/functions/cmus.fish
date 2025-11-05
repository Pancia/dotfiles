function cmus --description 'Start cmus with random mode' --wraps cmus
    sleep 1; and cmus-remote -C rand &
    env LC_ALL=C.UTF-8 command cmus $argv
end
