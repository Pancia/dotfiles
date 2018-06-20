source ~/dotfiles/antigen/antigen.zsh

antigen use oh-my-zsh

# Bundles from the default repo (robbyrussell's oh-my-zsh).
antigen bundle git
antigen bundle git-flow
antigen bundle lein
antigen bundle node
antigen bundle npm
antigen bundle python

# OSX
antigen bundle brew
antigen bundle brew-cask

# ZSH
antigen bundle zsh-users/zsh-syntax-highlighting
antigen bundle zsh-users/zsh-history-substring-search

# Load the theme.
antigen theme bhilburn/powerlevel9k powerlevel9k.zsh-theme

# Tell antigen that you're done.
antigen apply
