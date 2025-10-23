source ~/dotfiles/zsh/antigen.zsh
source ~/dotfiles/zsh/setup.zsh
source ~/dotfiles/zsh/functions.zsh
source ~/dotfiles/zsh/theme.zsh

TEMPLATES_PATH="$(llm templates path)"
if [ ! -L "$TEMPLATES_PATH" ]; then
    if [ -e "$TEMPLATES_PATH" ]; then
        echo "Warning: $TEMPLATES_PATH exists but is not a symbolic link"
    else
        ln -s ~/dotfiles/ai/templates/ "$TEMPLATES_PATH"
    fi
fi

export LAST_DIR=$HOME/.last_dir
echo "$PWD" > $LAST_DIR

function record_dir_change() {
    if [ "$(cat $LAST_DIR)" != "$PWD" ]
    then
        print -s "##dir## $PWD"
        echo "$PWD" > $LAST_DIR
    fi
}

function zshaddhistory() {
    record_dir_change
    return 0
}
