function wait-for {
    echo "[wait-for]: Waiting for \`test -e $1\`, will execute \`${@:2}\`"
    local i=0; while [ ! -e "$1" ]; do; sleep 1; ((i++)); echo -n "\rWaited: $i seconds"; done;
    echo -n "\nDone waiting for $1, executing: '${@:2}'."
    "${@:2}"
}

function watch {
    local cmd_file="$1"
    local args="${@:2}"
    local watch=".$(basename $cmd_file).watch"
    echo `stat -f%m $cmd_file` > $watch
    while true; do
        local mtime=`stat -f%m $cmd_file`
        if [ `cat $watch 2> /dev/null` != $mtime ]; then
            echo '======================'
            eval $cmd_file $args
            echo '======================'
            echo $mtime > $watch
        fi
        sleep 1
    done
}

function bak {
    if [ -e "$1.bak" ]; then bak "$1.bak"; fi
    cp "$1" "$1.bak"
}
function sponge() { local tmp="$(mktemp)"; bak "$1" && cat > "$tmp" && mv "$tmp" "$1" }

function cat { bat "$@" }
function less { bat "$@" }
function ls { command ls -h "$@" }
function reset { tput reset }

function vim { TERM_TYPE=nvim nvim "$@" }

function dot { cd ~/dotfiles; vim ~/dotfiles }
function vimrc { vim ~/dotfiles/nvim/init.vim }
function zshrc { vim ~/dotfiles/zsh/zshrc }
function .zshrc { exec zsh }
function .zsh { exec zsh }

function meditate {
    local T="$((60*${1:-5}))"
    echo "sleeping for $T seconds"
    cmus-remote --stop
    sleep $T
    echo "wakeup!"
    cmus-remote --play
}

local functions_dir=`dirname $0`/fns
for f in $(ls $functions_dir); do
    source $functions_dir/$f
done
