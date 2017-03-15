source ~/dotfiles/zsh/antigen.zsh
source ~/dotfiles/zsh/bindings.zsh

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
