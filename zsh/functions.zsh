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

function cat { command tail -n +1 "$@" }
function less { command less -N "$@" }
function ls { command ls -h "$@" }
function reset { tput reset }

function vim { TERM_TYPE=nvim nvim "$@" }
function vimrc { vim ~/dotfiles/nvim/init.vim }
function zshrc { vim ~/dotfiles/zsh/zshrc }
function .zshrc { exec zsh }
function .zsh { exec zsh }
function dot { vim ~/dotfiles }

local functions_dir=`dirname $0`/fns
for f in $(ls $functions_dir); do
    source $functions_dir/$f
done
