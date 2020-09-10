function reset { tput reset }

function vim { TERM_TYPE=nvim nvim "$@" }

function vimrc { vim ~/dotfiles/nvim/init.vim }
function zshrc { vim ~/dotfiles/zsh/zshrc }
function .zshrc { exec zsh }
function .zsh { exec zsh }

function ls { command ls -h "$@" }

function cat { bat "$@" }
function less { bat "$@" }

function meditate {
    local T="$((60*${1:-5}))"
    echo "sleeping for $T seconds"
    cmus-remote --stop
    sleep $T
    echo "wakeup!"
    cmus-remote --play
}

function __with_IFS {
  IFS='&';
  $($@);
  unset IFS;
}

local functions_dir=`dirname $0`/fns
for f in $(ls $functions_dir); do
    source $functions_dir/$f
done
