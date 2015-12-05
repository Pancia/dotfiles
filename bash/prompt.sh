# Add colors!
export CLICOLOR=1
export LSCOLORS=GxFxCxDxBxegedabagaced

#CUSTOM PROMPT
GB="@\$(git branch 2>/dev/null | grep '^*' | colrm 1 2)"
export PS1="[\w$GB]\nλ? "
