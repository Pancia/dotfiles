function _fancy-ctrl-z {
    if [[ $#BUFFER -eq 0 ]]; then
        if [[ "$(jobs | wc -l)" -gt 1 ]]; then
            BUFFER="jobs"
            zle accept-line
            zle -U "fg %"
            zle end-of-line
        else
            BUFFER="fg"
            zle accept-line
        fi
    else
        zle push-input
        zle clear-screen
    fi
}
zle -N _fancy-ctrl-z
bindkey '^Z' _fancy-ctrl-z
