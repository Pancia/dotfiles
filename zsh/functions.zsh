function reset { printf '\e]1337;ClearScrollback\a' }

function .zshrc { exec zsh }
function .zsh { exec zsh }

function ls { command ls -h "$@" }

function cat { bat "$@" }
function less { bat "$@" }

function ydl { yt-dlp "$@" }
function gdl { gallery-dl "$@" }

function cmus {
    (sleep 1 && cmus-remote -C rand) &
    LC_ALL=C.UTF-8 command cmus "$@"
}

function find { # find but prefer fd
    if [ -n $PS1 ]; then
        >&2 echo "[find] REMEMBER: use \`fd\`"
    fi
    command find "$@"
}


function c {
    cd $HOME
    local dir
    dir=$(fd --type d --max-depth 4 --follow --hidden | \
            fzf --tac --no-sort \
                --preview='ls -Fh --color=always {}' \
                --preview-window=right:50%)
    if [ -n "$dir" ]; then
        cd "$dir" && echo ls && ls
    else
        cd -
    fi
}

function v {
    local file
    file=$(fd --type f --follow --hidden | \
            fzf --tac --no-sort \
                --preview='bat --style=numbers --color=always {} 2>/dev/null || cat {}' \
                --preview-window=right:50%)
    if [ -n "$file" ]; then
        nvim "$file"
    fi
}

function meditate {
    local T="$((60*${1:-5}))"
    echo "sleeping for $T seconds"
    cmus-remote --stop
    sleep $T
    echo "wakeup!"
    cmus-remote --play
}

function heater {
    set -o localoptions -o localtraps
    trap 'killall yes' EXIT
    yes > /dev/null &
    yes > /dev/null &
    yes > /dev/null &
    sudo powermetrics --samplers smc | ag '(CPU.*temp|Fan)'
}

local functions_dir=`dirname $0`/fns
for f in $(ls $functions_dir); do
    source $functions_dir/$f
done
