# PATH MODIFICATIONS
export PATH=/usr/local/bin:$PATH
export PATH="/opt/local/bin:/opt/local/sbin:$PATH"
export PATH=$PATH:~/.gradle/wrapper/dists/gradle-1.11-all/7qd8qq8te5j4f5q9aaei3gh3lj/gradle-1.11/bin/
### Added by the Heroku Toolbelt
export PATH="/usr/local/heroku/bin:$PATH"
export PATH=$HOME/.cabal/bin:$PATH
export PATH=$HOME/loki/.cabal-sandbox/bin/:$PATH

#For UniBull & Postgres DB
export DB_NAME="pancia"
export DB_USERNAME="pancia"

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

# Add colors!
export CLICOLOR=1
export LSCOLORS=GxFxCxDxBxegedabagaced

# For ignoring spaces and duplicates in bash history
export HISTCONTROL=ignoreboth:erasedups
# Disable EOF (<c-d>) closing terminal
set -o ignoreeof
# Dont autocomplete hidden files
bind 'set match-hidden-files off'

function _maybe_mv {
local src="$1"
local target="$2"
[ -d "$target" ] && target="${target%/}/$src"
echo "\"$target\" already exists! Do you want to..."
select choice in "overwrite" "backup" "skip"; do
    case $choice in
        overwrite ) command mv "$src" "$target"
                    break;;

        backup )    mv "$target" "$target.bak"
                    command mv "$src" "$target"
                    break;;

        skip )      break;;
    esac
done
}

function mv {
local target="${@: -1}"
if [ -d "$target" ]; then
    local sources="${@:1:$(($#-1))}"
    for src in $sources; do
        if [ -e "${target%/}/$src" ]; then
            _maybe_mv "$src" "$target"
        else
            command mv "$src" "$target/$src"
        fi
    done
else
    local src="$1"
    if [ -e "$target" ]; then
        _maybe_mv "$src" "$target"
    else
        command mv "$src" "$target"
    fi
fi
}

function _maybe_cp {
local src="$1"
local target="$2"
[ -d "$target" ] && target="${target%/}/$src"
echo "\"$target\" already exists! Do you want to..."
select choice in "overwrite" "backup" "skip"; do
    case $choice in
        overwrite ) command cp "$src" "$target"
                    break;;

        backup )    mv "$target" "$target.bak"
                    command cp "$src" "$target"
                    break;;

        skip )      break;;
    esac
done
}

function cp {
local target="${@: -1}"
if [ -d "$target" ]; then
    local sources="${@:1:$(($#-1))}"
    for src in $sources; do
        if [ -e "${target%/}/$src" ]; then
            _maybe_cp "$src" "$target"
        else
            command cp "$src" "$target/$src"
        fi
    done
else
    local src="$1"
    if [ -e "$target" ]; then
        _maybe_cp "$src" "$target"
    else
        command cp "$src" "$target"
    fi
fi
}

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
