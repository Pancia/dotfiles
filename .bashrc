# PATH MODIFICATIONS
export PATH=/usr/local/bin:$PATH
export PATH="/opt/local/bin:/opt/local/sbin:$PATH"
export PATH=$PATH:~/.gradle/wrapper/dists/gradle-1.11-all/7qd8qq8te5j4f5q9aaei3gh3lj/gradle-1.11/bin/
### Added by the Heroku Toolbelt
export PATH="/usr/local/heroku/bin:$PATH"
export PATH=$HOME/.cabal/bin:$PATH
export PATH=$HOME/.local/bin/:$PATH
export PATH=$HOME/loki/.cabal-sandbox/bin/:$PATH
export PATH=$HOME/Library/Android/sdk/platform-tools/:$PATH

# bash-completion - installed with macports
if [ -f /opt/local/etc/profile.d/bash_completion.sh ]; then
    source /opt/local/etc/profile.d/bash_completion.sh
fi
source ~/.git-completion.bash

# node, if no args use repl.history
function node {
    if test "$#" -lt 1; then
        repl.history
    else
        env node $@;
    fi;
}

#For UniBull & Postgres DB
export DB_NAME="pancia"
export DB_USERNAME="pancia"

#For Spotify-To-Youtube/JSON
export SPOTIFY_APP_SECRET="1370adea9e694c29a598e92b78a528d6";

#For slimerjs & cljs testing
export SLIMERJSLAUNCHER=/Applications/Firefox.app/Contents/MacOS/firefox

# Custom Prompt
export PS1="[\u@\w]?"

# ALIASES
alias vim='/Applications/MacVim.app/Contents/MacOS/Vim'
alias vimrc='vim ~/.vimrc -c "cd ~/.vim"'
alias help='echo "vimrc, [show|hide]Files, ip, pl, ucsc, todo, [.]bashrc, loki"'
alias showFiles='defaults write com.apple.finder AppleShowAllFiles YES'
alias hideFiles='defaults write com.apple.finder AppleShowAllFiles NO'
alias ip='ifconfig | grep -oe "inet 192.168.1.[0-9]\+" | head -n 1'
alias pl='/Applications/SWI-Prolog.app/Contents/MacOS/swipl'
alias ucsc='ssh adambros@unix.ucsc.edu'
alias todo='grep -Iir "todo" *'
alias bashrc='vim ~/.bashrc'
alias .bashrc='source ~/.bashrc'
alias cat='tail -n +1' # Will show files names if # files>1
alias ls='ls -h'
alias clear='clear ; echo -e "\e[3J"'
alias patch='git pull && npm version patch && git push && git push --tags && npm publish --registry https://registry.npmjs.org'
alias minor='git pull && npm version minor && git push && git push --tags && npm publish --registry https://registry.npmjs.org'
alias major='git pull && npm version major && git push && git push --tags && npm publish --registry https://registry.npmjs.org'

# Add colors!
export CLICOLOR=1
export LSCOLORS=GxFxCxDxBxegedabagaced

# For ignoring spaces and duplicates in bash history
export HISTCONTROL=ignoreboth:erasedups
# Disable EOF (<c-d>) closing terminal
set -o ignoreeof
# Dont autocomplete hidden files
bind 'set match-hidden-files off'

function cdd {
    cd ~/projects/$@
}
#Autocomplete for cdd
function _projdirs {
    local curw
    COMPREPLY=()
    curw=${COMP_WORDS[COMP_CWORD]}
    COMPREPLY=($(compgen -W '`find ~/projects -depth 2 -type d | cut -c 24-`' -- $curw))
    return 0
}
complete -F _projdirs -o dirnames cdd

# Move to the trash instead
function rm {
local dir prefix timestamp
dir="$(pwd)"
timestamp="$(date '+%Y-%m-%d_%X')"
prefix="${dir//\//%}T${timestamp}<->"
for i in "$@"; do
    command mv "$i" "$HOME/.Trash/${prefix}${i//\//%}"
done
}

###-begin-mercury-completion-###
### credits to npm, this file is coming directly from isaacs/npm repo
# Copyright (c) npm, Inc. and Contributors
# All rights reserved.
#
# Just testing for now. (trying to learn this cool stuff)
#
# npm command completion script
#
# Installation: mercury completion >> ~/.bashrc  (or ~/.zshrc)
#

COMP_WORDBREAKS=${COMP_WORDBREAKS/=/}
COMP_WORDBREAKS=${COMP_WORDBREAKS/@/}
export COMP_WORDBREAKS

if complete &>/dev/null; then
  _mercury_completion () {
    local si="$IFS"
    IFS=$'\n' COMPREPLY=($(COMP_CWORD="$COMP_CWORD" \
                           COMP_LINE="$COMP_LINE" \
                           COMP_POINT="$COMP_POINT" \
                           mercury completion -- "${COMP_WORDS[@]}" \
                           2>/dev/null)) || return $?
    IFS="$si"
  }
  complete -F _mercury_completion -o default mercury
elif compctl &>/dev/null; then
  _mercury_completion () {
    local cword line point words si
    read -Ac words
    read -cn cword
    let cword-=1
    read -l line
    read -ln point
    si="$IFS"
    IFS=$'\n' reply=($(COMP_CWORD="$cword" \
                       COMP_LINE="$line" \
                       COMP_POINT="$point" \
                       mercury completion -- "${words[@]}" \
                       2>/dev/null)) || return $?
    IFS="$si"
  }
  compctl -K _mercury_completion -f mercury
fi
###-end-mercury-completion-###

###-begin-npm-completion-###
#
# npm command completion script
#
# Installation: npm completion >> ~/.bashrc  (or ~/.zshrc)
# Or, maybe: npm completion > /usr/local/etc/bash_completion.d/npm
#

COMP_WORDBREAKS=${COMP_WORDBREAKS/=/}
COMP_WORDBREAKS=${COMP_WORDBREAKS/@/}
export COMP_WORDBREAKS

if type complete &>/dev/null; then
  _npm_completion () {
    local si="$IFS"
    IFS=$'\n' COMPREPLY=($(COMP_CWORD="$COMP_CWORD" \
                           COMP_LINE="$COMP_LINE" \
                           COMP_POINT="$COMP_POINT" \
                           npm completion -- "${COMP_WORDS[@]}" \
                           2>/dev/null)) || return $?
    IFS="$si"
  }
  complete -o default -F _npm_completion npm
elif type compdef &>/dev/null; then
  _npm_completion() {
    local si=$IFS
    compadd -- $(COMP_CWORD=$((CURRENT-1)) \
                 COMP_LINE=$BUFFER \
                 COMP_POINT=0 \
                 npm completion -- "${words[@]}" \
                 2>/dev/null)
    IFS=$si
  }
  compdef _npm_completion npm
elif type compctl &>/dev/null; then
  _npm_completion () {
    local cword line point words si
    read -Ac words
    read -cn cword
    let cword-=1
    read -l line
    read -ln point
    si="$IFS"
    IFS=$'\n' reply=($(COMP_CWORD="$cword" \
                       COMP_LINE="$line" \
                       COMP_POINT="$point" \
                       npm completion -- "${words[@]}" \
                       2>/dev/null)) || return $?
    IFS="$si"
  }
  compctl -K _npm_completion npm
fi
###-end-npm-completion-###
