# Add colors!
export CLICOLOR=1
export LSCOLORS=GxFxCxDxBxegedabagaced

#CUSTOM PROMPT
export PS1="λ? "
GB="@\$(git branch 2>/dev/null | grep '^*' | colrm 1 2)"
PS1_MODE=0
function p() {
if [ "$1" ] ;then
    PS1_MODE=$((($1 + 1) % 2))
    p
fi

case "$PS1_MODE" in
    0)
        PS1_MODE=1
        export PS1="[\w$GB]\nλ? "
        ;;
    1)
        PS1_MODE=0
        export PS1="λ? "
        ;;
    *) echo "err($PS1_MODE)"
        PS1_MODE=0
        export PS1="λ? "
        ;;
esac
}
alias p0="p 0"
alias p1="p 1"
