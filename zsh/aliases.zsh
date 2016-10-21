alias vim='TERM_TYPE=nvim nvim'
alias vimrc='vim ~/dotfiles/nvim/init.vim -c "cd ~/dotfiles/nvim"'
alias vims='vim -S ~/dotfiles/Session.vim'
alias vimsession='vim -S ~/dotfiles/Session.vim'

alias a='fasd -a'
alias d='fasd -d'
alias f='fasd -f'
alias s='fasd -si'
alias sd='fasd -sid'
alias sf='fasd -sif'
alias z='fasd_cd -d'
alias zz='fasd_cd -d -i'
alias v='fasd -f -e nvim'

alias showFiles='defaults write com.apple.finder AppleShowAllFiles YES'
alias hideFiles='defaults write com.apple.finder AppleShowAllFiles NO'

alias todo='ag -i todo'

alias zshrc='vim ~/dotfiles/zshrc'
alias .zshrc='source ~/dotfiles/zshrc'

alias .lein='vim ~/.lein/profiles.clj'
alias .prof='vim ~/.lein/profiles.clj'
alias .profile='vim ~/.lein/profiles.clj'

alias lc='lein clean'
alias ltr='rlwrap lein test-refresh'
alias ltrc='rlwrap lein do clean, test-refresh'
alias lr='lein repl'
alias lrc='lein do repl, clean'
alias 'lr:'='lein repl :connect'

alias cat='tail -n +1' # Will show files names if # files>1
alias ls='ls -h'
alias gitroot='git rev-parse --show-toplevel'

alias cljs='planck'

alias _gitignore_to_regex="(cat .gitignore 2> /dev/null || echo '') | sed 's/^\///' | tr '\n' '|'"
alias tree='tree -I $(_gitignore_to_regex)'
alias ag='ag --hidden'

alias reset='tput reset'

alias help!="ag '^alias [^=]+?=' ~/dotfiles/zsh/aliases.zsh"
alias help="help! -o | ag -o ' [^=]+=$' | ag -o '[^=]+' | xargs"
