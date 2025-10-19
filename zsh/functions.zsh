function reset { printf '\e]1337;ClearScrollback\a' }

function .zshrc { exec zsh }
function .zsh { exec zsh }

function ls { command ls -h "$@" }

function cat { bat "$@" }
function less { bat "$@" }

function ydl { yt-dlp "$@" }
function gdl { gallery-dl "$@" }

function cmus { LC_ALL=C.UTF-8 command cmus "$@" }

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
