#PATH MODIFICATIONS
export PATH=/usr/local/bin:$PATH
export PATH="/opt/local/bin:/opt/local/sbin:$PATH"
export PATH=$PATH:~/.gradle/wrapper/dists/gradle-1.11-all/7qd8qq8te5j4f5q9aaei3gh3lj/gradle-1.11/bin/
### Added by the Heroku Toolbelt
export PATH="/usr/local/heroku/bin:$PATH"
export PATH=$HOME/.cabal/bin:$PATH
export PATH=$HOME/loki/.cabal-sandbox/bin/:$PATH

export PS1="[\u@\w]?"

alias help='echo "[show|hide]Files, ip, pl, ucsc, todo, [.]bashrc, loki"'
alias showFiles='defaults write com.apple.finder AppleShowAllFiles YES'
alias hideFiles='defaults write com.apple.finder AppleShowAllFiles NO'
alias ip='ifconfig | grep -oe "inet 192.168.1.[0-9]\+" | head -n 1'
alias pl='/Applications/SWI-Prolog.app/Contents/MacOS/swipl'
alias ucsc='ssh adambros@unix.ucsc.edu'
alias todo='grep -Iir "todo" *'
alias bashrc='vim ~/.bashrc'
alias .bashrc='source ~/.bashrc'
alias cat='tail -n +1 $*' #will show files names if #files>1
alias cp='cp -n $*' #will not overwrite
alias mv='mv -n $*' #will not overwrite

#Cleans trashbin
function cln {
    command rm ~/.Trash/*
}

#Overrides rm to move it to the ~/.Trash (with a prefix)
#TODO: Add a timestamp prefix
function rm {
    local dir="$(pwd)"
    for i in "$@"; do
        local prefix=${dir//\//\_}
        prefix=${prefix:(-20)}
        mv $i ~/.Trash/${prefix}_${i}
    done
}

#For ignoring spaces and duplicates in bash history
export HISTCONTROL=ignoreboth:erasedups
