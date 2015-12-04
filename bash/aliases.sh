alias vim='TV=1 /Applications/MacVim.app/Contents/MacOS/Vim'
alias vimrc='vim ~/cfg/vimrc -c "cd ~/.vim"'
alias showFiles='defaults write com.apple.finder AppleShowAllFiles YES'
alias hideFiles='defaults write com.apple.finder AppleShowAllFiles NO'
alias ucsc='ssh adambros@unix.ucsc.edu'
alias todo='grep -Iir "todo" *'
alias bashrc='vim ~/cfg/bashrc'
alias .bashrc='source ~/cfg/bashrc'
alias cat='tail -n +1' # Will show files names if # files>1
alias ls='ls -h'
alias fw='rlwrap lein run -m clojure.main'
alias gitroot='git rev-parse --show-toplevel'

alias help="ag '^alias [^=]+?=' ~/.bashrc -o | ag -o ' [^=]+=$' | ag -o '[^=]+' | xargs"
alias help!="ag '^alias [^=]+?=' ~/.bashrc"
