local functions_dir=`dirname $0`/fns
for f in $(ls $functions_dir); do
    source $functions_dir/$f
done

function rm {
    local dir prefix timestamp failed
    dir="$(pwd)"
    timestamp="$(date '+%Y-%m-%d_%X')"
    prefix="${dir//\//%}T${timestamp}<->"
    failed=false
    for f in "$@"; do
        if [ -e $f ]; then
            echo "moved ${f} to" ~/.Trash/${prefix}${f//\//%}
            mv ${f} ~/.Trash/${prefix}${f//\//%}
        else
            failed=true
            echo "[dotfiles/rm] file not found: $f" >&2
        fi
    done
    $failed && return 1
}

function _fancy-ctrl-z {
    if [[ $#BUFFER -eq 0 ]]; then
        if [[ "$(jobs | wc -l)" -gt 1 ]]; then
            BUFFER="jobs"
            zle accept-line
            zle -U "fg %"
            zle end-of-line
        else
            BUFFER="fg"
            zle accept-line
        fi
    else
        zle push-input
        zle clear-screen
    fi
}
zle -N _fancy-ctrl-z
bindkey '^Z' _fancy-ctrl-z

function vim { TERM_TYPE=nvim nvim "$@" }
function vimrc { vim ~/dotfiles/nvim/init.vim -c "cd ~/dotfiles/nvim" }

function a { fasd -a "$@" }
function d { fasd -d "$@" }
function f { fasd -f "$@" }
function s { fasd -si "$@" }
function sd { fasd -sid "$@" }
function sf { fasd -sif "$@" }
function z { fasd_cd -d "$@" }
function zz { fasd_cd -d -i "$@" }
function v { fasd -f -e nvim "$@" }

function showFiles { defaults write com.apple.finder AppleShowAllFiles YES }
function hideFiles { defaults write com.apple.finder AppleShowAllFiles NO }

function todo { ag -i todo "$@" }

function zshrc { vim ~/dotfiles/zshrc }

function .lein { vim ~/.lein/profiles.clj }
function .prof { vim ~/.lein/profiles.clj }
function .profile { vim ~/.lein/profiles.clj }
function lc { lein clean }
function ltr { rlwrap lein test-refresh }
function ltrc { rlwrap lein do clean, test-refresh }
function lr { lein repl }
function lrc { lein do clean, repl"$@" }
function lr: { lein repl :connect }
function _with_out { (echo "$@"; command cat <&0) }
function lrw { (_with_out "$@") | lein repl }
function lrcw { (_with_out "$@") | lein do repl, clean }
function lr:w { (_with_out "$@") | lein repl :connect }

function wait-for {
    local i=0; while [ ! -e "$1" ]; do; sleep 1; ((i++)); echo -n "\rWaited: $i seconds"; done;
    echo -n "\nDone waiting for $1"; shift; echo ", executing: '$@'."
    "$@"
}

function cat { command tail -n +1 "$@" }
function less { command less -N "$@" }
function ls { command ls -h "$@" }

function gitroot { git rev-parse --show-toplevel "$@" }

function cljs { planck "$@" }

function _gitignore_to_regex {
    (command cat .gitignore .ignore ~/.ignore ~/dotfiles/git/gitignore_global 2> /dev/null || echo '') \
        | sed '/^[#;"]/d' \
        | sed 's#^/##' \
        | tr '\n' '|' \
        | sed 's/\|*$//'
}
function tree { command tree -I "$(_gitignore_to_regex)" "$@" }

function ag { command ag --hidden "$@" }

function reset { tput reset }

function playMusic { player-rs "$@" }

function cache {
    local cache_root="$HOME/.cache/dot-cache"

    case "$1" in
        clear|purge) command rm -r $cache_root ;;
        *)
            local stamp_file="$cache_root/`pwd`/cache.$1.date"
            local interval="$2"
            local now=$(date +%s 2>/dev/null)
            local last=$(cat $stamp_file 2>/dev/null || echo '0')

            local SEC_TO_MIN=60
            local delta=$(($now-$last))
            interval=$(($interval*$SEC_TO_MIN))
            if [ $delta -ge $interval ]; then
                local script="$(cat /dev/stdin)"
                zsh -c "$script"
                mkdir -p "$(dirname $stamp_file)" && echo "$now" > $stamp_file
            fi
            ;;
    esac
}

function chpwd {
    cache chpwd 15 <<EOC
[ -e TODO ] && cat TODO
vims list 2> /dev/null
EOC
}
chpwd
