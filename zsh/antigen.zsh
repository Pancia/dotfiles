source ~/dotfiles/antigen/antigen.zsh

antigen use oh-my-zsh

# SHELL & CO.
antigen bundle git
antigen bundle lein
antigen bundle node
antigen bundle npm
antigen bundle osx
antigen bundle python

# OSX
antigen bundle brew
antigen bundle brew-cask

# ZSH
antigen bundle zsh-users/zsh-autosuggestions
antigen bundle popstas/zsh-command-time
#antigen bundle rocky/zshdb # TODO FIXME
antigen bundle zsh-users/zsh-history-substring-search
antigen bundle zsh-users/zsh-syntax-highlighting

# THEME
antigen theme bhilburn/powerlevel9k powerlevel9k.zsh-theme
#antigen bundle ex-surreal/randeme # TODO FIXME

antigen apply
