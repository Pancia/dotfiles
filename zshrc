function PROF_GO {
    # set the trace prompt to include seconds, nanoseconds, script name and line number
    zmodload zsh/datetime
    setopt promptsubst
    PS4='%D{%M%S%.} %N:%i> '
    # save file stderr to file descriptor 3 and redirect stderr (including trace output)
    exec 3>&2 2>/tmp/zsh-profiling.$$.log
    # set options to turn on tracing and expansion of commands contained in the prompt
    setopt xtrace prompt_subst
    zmodload zsh/zprof
}
#PROF_GO # uncomment to profile zsh startup, DONT FORGET to `PROF_NO` at the end

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

function PROF_NO {
    # turn off tracing
    unsetopt xtrace
    # restore stderr to the value saved in FD 3
    exec 2>&3 3>&-
    zprof > /tmp/zprof.$$.log
}
#PROF_NO # uncomment to finish profiling after doing `PROF_GO`
