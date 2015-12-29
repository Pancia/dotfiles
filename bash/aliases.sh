alias vim='TV=1 /Applications/MacVim.app/Contents/MacOS/Vim'
alias vimrc='vim ~/dotfiles/vimrc -c "cd ~/.vim"'
alias showFiles='defaults write com.apple.finder AppleShowAllFiles YES'
alias hideFiles='defaults write com.apple.finder AppleShowAllFiles NO'
alias ucsc='ssh adambros@unix.ucsc.edu'

alias todo='ag -i todo'

alias bashrc='vim ~/dotfiles/bashrc'
alias .bashrc='source ~/dotfiles/bashrc'
alias cat='tail -n +1' # Will show files names if # files>1
alias ls='ls -h'
alias fw='rlwrap lein run -m clojure.main'
alias gitroot='git rev-parse --show-toplevel'

alias cljs='planck'

alias reset='tput reset'

alias _gitignore_to_regex="(cat .gitignore 2> /dev/null || echo '') | sed 's/^\///' | tr '\n' '|'"
alias tree='tree -I $(_gitignore_to_regex)'
alias ag='ag --hidden'
alias help="ag '^alias [^=]+?=' ~/dotfiles/bash/aliases.sh -o | ag -o ' [^=]+=$' | ag -o '[^=]+' | xargs"
alias help!="ag '^alias [^=]+?=' ~/dotfiles/bash/aliases"
