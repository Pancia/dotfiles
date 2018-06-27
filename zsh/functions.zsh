local functions_dir=`dirname $0`/fns
for f in $(ls $functions_dir); do
    source $functions_dir/$f
done

function wait-for {
    echo "[wait-for]: Waiting for \`test -e $1\`, will execute \`${@:2}\`"
    local i=0; while [ ! -e "$1" ]; do; sleep 1; ((i++)); echo -n "\rWaited: $i seconds"; done;
    echo -n "\nDone waiting for $1, executing: '${@:2}'."
    "$@"
}

function cat { command tail -n +1 "$@" }
function less { command less -N "$@" }
function ls { command ls -h "$@" }
function reset { tput reset }

function vim { TERM_TYPE=nvim nvim "$@" }
function vimrc { vim ~/dotfiles/nvim/init.vim }
function zshrc { vim ~/dotfiles/zsh/zshrc }
function dot { vim ~/dotfiles }
