function reset { tput reset }

function vim { TERM_TYPE=nvim nvim "$@" }

function vimrc { vim ~/dotfiles/nvim/init.vim }
function zshrc { vim ~/dotfiles/zsh/zshrc }
function .zshrc { exec zsh }
function .zsh { exec zsh }

function ls { command ls -h "$@" }

function cat { bat "$@" }
function less { bat "$@" }

function home { itermocil home; cmus }

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
