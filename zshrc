function ZSHRC {
    source ~/dotfiles/zsh/antigen.zsh
    source ~/dotfiles/zsh/bindings.zsh
    source ~/dotfiles/zsh/config.zsh

    source ~/dotfiles/zsh/git-fns.zsh

    source ~/dotfiles/zsh/functions.zsh
    source ~/dotfiles/zsh/theme.zsh

    [ -e ~/dotfiles/extra.zsh ] && source ~/dotfiles/extra.zsh

    if [[ $1 == eval ]]; then
        shift
        ICMD="$@"
        set --
        function zle-line-init {
            BUFFER="$ICMD"
            zle accept-line
            zle -D zle-line-init
        }
        zle -N zle-line-init
    fi
}

local ZSH_PROF_LOG="/tmp/zsh-profiling.$$.log"
local ZPROF_LOG="/tmp/zprof.$$.log"
function PROF_GO {
    trap "
    # set the trace prompt to include seconds, nanoseconds, script name and line number
    zmodload zsh/datetime
    setopt promptsubst prompt_subst
    PS4='%D{%M%S%.} %N:%i> '
    # save file stderr to file descriptor 3 and redirect stderr (including trace output)
    exec 3>&2 2>$ZSH_PROF_LOG
    setopt xtrace
    " EXIT
    zmodload zsh/zprof
}

function PROF_NO {
    trap '
    unsetopt xtrace
    # restore stderr to the value saved in FD 3
    exec 2>&3 3>&-
    ' EXIT
    zprof > $ZPROF_LOG
}

[[ 1 == $PROF ]] &&
    PROF_GO
ZSHRC; local X=$?
[[ 1 == $PROF ]] &&
    PROF_NO &&
    export PROF=0 &&
    less $ZSH_PROF_LOG $ZPROF_LOG
exit $X
