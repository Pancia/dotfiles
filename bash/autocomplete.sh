# bash-completion - installed with macports
if [ -f /opt/local/etc/bash_completion ]; then
    source /opt/local/etc/bash_completion
fi

# For ignoring spaces and duplicates in bash history
export HISTCONTROL=ignoreboth:erasedups
# Disable EOF (<c-d>) closing terminal
set -o ignoreeof
# Dont autocomplete hidden files
bind 'set match-hidden-files off'

# Autocomplete using up and down arrow keys
bind '"\e[A": history-search-backward'
bind '"\e[B": history-search-forward'
bind 'set show-all-if-ambiguous on'
bind 'set completion-ignore-case on'
