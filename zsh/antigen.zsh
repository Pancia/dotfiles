source ~/dotfiles/antigen/antigen.zsh

autoload -Uz compinit && compinit
function __eval_completion { IFS='&'; $($@); unset IFS; }
function _ENSURE_COMPLETIONS {
    for f in $(ls $HOME/dotfiles/bin/*); do
        local compdef="$(cat $f | sed -n '2p')"
        if [[ $compdef =~ 'zsh-completion' ]]; then
            local completion="$(echo "$compdef" | sed -E 's/.*<\[zsh-completion\]>:(.*)/\1/')"
            compdef "__eval_completion $completion" $(basename $f)
        fi
    done
}
_ENSURE_COMPLETIONS

antigen use oh-my-zsh

# SHELL & CO.
antigen bundle git

# OSX
antigen bundle brew
antigen bundle brew-cask

# ZSH
antigen bundle zsh-users/zsh-autosuggestions
antigen bundle popstas/zsh-command-time
antigen bundle zsh-users/zsh-history-substring-search
antigen bundle zsh-users/zsh-syntax-highlighting

# THEME
antigen theme bhilburn/powerlevel9k powerlevel9k.zsh-theme
#antigen bundle ex-surreal/randeme # TODO FIXME

antigen apply
