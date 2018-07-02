source ~/dotfiles/antigen/antigen.zsh

antigen use oh-my-zsh

# SHELL & CO.
antigen bundle fasd
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
antigen bundle zsh-users/zsh-autosuggestions
antigen bundle popstas/zsh-command-time
antigen bundle cal2195/q
antigen bundle zsh-users/zsh-syntax-highlighting
antigen bundle zsh-users/zsh-history-substring-search

# THEME
antigen theme bhilburn/powerlevel9k powerlevel9k.zsh-theme

antigen apply
