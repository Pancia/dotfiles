alias vim='TV=1 /Applications/MacVim.app/Contents/MacOS/Vim'
alias vimrc='vim ~/dotfiles/vimrc -c "cd ~/.vim"'

alias gs='git status'
alias gd='git diff --color-words'
alias gds='gd --staged'
alias gl='GIT_PAGER="less -p \"\(HEAD\"" git log --graph --all --decorate --abbrev-commit'

alias showFiles='defaults write com.apple.finder AppleShowAllFiles YES'
alias hideFiles='defaults write com.apple.finder AppleShowAllFiles NO'

alias todo='ag -i todo'

alias zshrc='vim ~/dotfiles/zshrc'
alias .zshrc='source ~/dotfiles/zshrc'

alias .lein='vim ~/.lein/profiles.clj'
alias .prof='vim ~/.lein/profiles.clj'
alias .profile='vim ~/.lein/profiles.clj'

alias cat='tail -n +1' # Will show files names if # files>1
alias ls='ls -h'
alias fw='rlwrap lein run -m clojure.main'
alias gitroot='git rev-parse --show-toplevel'

alias cljs='planck'

alias _gitignore_to_regex="(cat .gitignore 2> /dev/null || echo '') | sed 's/^\///' | tr '\n' '|'"
alias tree='tree -I $(_gitignore_to_regex)'
alias ag='ag --hidden'

alias reset='tput reset'

alias help!="ag '^alias [^=]+?=' ~/dotfiles/zsh/aliases.zsh ~/dotfiles/zsh/gitcomplete.sh"
alias help="help! -o | ag -o ' [^=]+=$' | ag -o '[^=]+' | xargs"
