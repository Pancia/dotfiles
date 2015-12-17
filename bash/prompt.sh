# Add colors!
export CLICOLOR=1
export LSCOLORS=GxFxCxDxBxegedabagaced

#CUSTOM PROMPT
GB="@\$(git branch 2>/dev/null | grep '^*' | colrm 1 2)"
export PS1="\e[1;31m[\w$GB]\nλ? \e[0m"
