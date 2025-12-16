# enable `history` timestamps
setopt EXTENDED_HISTORY

# disable ctrl-d exiting shell
setopt IGNORE_EOF

# dont remember lines that start with a space
setopt HIST_IGNORE_SPACE

# bind UP and DOWN arrow keys
zmodload zsh/terminfo
bindkey "$terminfo[kcuu1]" history-substring-search-up
bindkey "$terminfo[kcud1]" history-substring-search-down

# bind k and j for VI mode
bindkey -M vicmd 'k' history-substring-search-up
bindkey -M vicmd 'j' history-substring-search-down
