export CLICOLOR=1
export LSCOLORS=GxFxCxDxBxegedabagaced

# http://wiki.bash-hackers.org/scripting/terminalcodes#general_text_attributes
COL_RED="$(tput setaf 1)"
COL_BOLD="$(tput bold)"
COL_RESET="$(tput sgr0)"

GB="@\$(git branch 2>/dev/null | grep '^*' | colrm 1 2)"

export PS1="\[$COL_RED$COL_BOLD\][\w$GB]\nλ? \[$COL_RESET\]"
