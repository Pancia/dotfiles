#PATH MODIFICATIONS
export PATH=/usr/local/bin:$PATH
export PATH="/opt/local/bin:/opt/local/sbin:$PATH"
export PATH=$PATH:~/.gradle/wrapper/dists/gradle-1.11-all/7qd8qq8te5j4f5q9aaei3gh3lj/gradle-1.11/bin/
### Added by the Heroku Toolbelt
export PATH="/usr/local/heroku/bin:$PATH"
export PATH=$HOME/.cabal/bin:$PATH
export PATH=$HOME/loki/.cabal-sandbox/bin/:$PATH

export PS1="[\u@\w]?"

#ALIASES
alias vim='/Applications/MacVim.app/Contents/MacOS/Vim'
alias vimrc='vim ~/.vimrc -c "cd ~/.vim"'
alias help='echo "[show|hide]Files, ip, pl, ucsc, todo, [.]bashrc, loki"'
alias showFiles='defaults write com.apple.finder AppleShowAllFiles YES'
alias hideFiles='defaults write com.apple.finder AppleShowAllFiles NO'
alias ip='ifconfig | grep -oe "inet 192.168.1.[0-9]\+" | head -n 1'
alias pl='/Applications/SWI-Prolog.app/Contents/MacOS/swipl'
alias ucsc='ssh adambros@unix.ucsc.edu'
alias todo='grep -Iir "todo" *'
alias bashrc='vim ~/.bashrc'
alias .bashrc='source ~/.bashrc'
alias cat='tail -n +1' #will show files names if #files>1
alias ls='ls -h'
alias mv='mv -i'
alias cp='cp -i'

#Add colors!
export CLICOLOR=1
export LSCOLORS=GxFxCxDxBxegedabagaced

#For ignoring spaces and duplicates in bash history
export HISTCONTROL=ignoreboth:erasedups
#disable EOF (<c-d>) closing terminal
set -o ignoreeof

#Move to the trash instead
rm() {
    local dir prefix timestamp
    dir="$(pwd)"
    timestamp="$(date '+%Y-%m-%d_%X')"
    prefix="${dir//\//_}_${timestamp}__"
    for i in "$@"; do
        #echo "$i $HOME/.Trash/${prefix}${i}"
        mv $i "$HOME/.Trash/${prefix}${i}"
    done
}
