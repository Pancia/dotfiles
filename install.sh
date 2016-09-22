#!/usr/bin/env bash
set -o errexit
([[ -n "$DEBUG" ]] || [[ -n "$TRACE" ]]) && set -o xtrace

task_git () {
    git pull && git submodule init &&
        git pull --recurse-submodules &&
        git submodule update --recursive
}

task_brew () {
    hash brew || (ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)")
    brew update
    brew bundle -v
}

task_gitconfig () {
    ln -f gitconfig ~/.gitconfig
    read -p 'git config user.email please: ' git_config_user_email
    git config --global user.email "$git_config_user_email"
    for i in $(ls ./git/hooks/*.tmpl); do
        ln -f $i /usr/local/share/git-core/templates/hooks/$(basename $i .tmpl)
    done
}

task_fonts () {
    [[ -e fonts ]] || (git clone https://github.com/powerline/fonts.git && ./fonts/install.sh)
}

task_rcs () {
    cp .vimperatorrc ~/.vimperatorrc
    cp .agignore     ~/.agignore
}

task_lein () {
    mkdir -p ~/.lein
    ln -f lein/profiles.clj ~/.lein/profiles.clj
}

task_zsh () {
    cp .zshrc  ~/.zshrc
    cp .zshenv ~/.zshenv
}

task_vim () {
    ln -f .vimrc ~/.vimrc
    mkdir -p ~/.vim/undo
    mkdir -p ~/.vim/ftplugin
    for i in $(ls vim/ftplugin); do
        echo "source ~/dotfiles/vim/ftplugin/$i" > ~/.vim/ftplugin/$i
    done
}

task_neovim () {
    pip3 install neovim-remote
    pip install --upgrade neovim
    mkdir -p ~/.config/nvim/ftplugin
    mkdir -p ~/.config/nvim/undo
    ln -f nvim/init.vim ~/.config/nvim/init.vim
    for i in $(ls nvim/ftplugin); do
        echo "source ~/dotfiles/nvim/ftplugin/$i" > ~/.config/nvim/ftplugin/$i
    done
}

task_bin () {
    for i in $(ls bin); do
        ln -f bin/$i /usr/local/bin/$i
    done
}

task_all () {
    task_git
    task_brew
    task_gitconfig
    task_fonts
    task_rcs
    task_lein
    task_vim
    task_neovim
    task_bin
    task_zsh
}

main() {
    case "$1" in
        git) task_git ;;
        brew) task_brew ;;
        gitconfig) task_gitconfig ;;
        fonts) task_fonts ;;
        rcs) task_rcs ;;
        zsh) task_zsh ;;
        vim) task_vim ;;
        neovim) task_neovim ;;
        nvim) task_neovim ;;
        bin) task_bin ;;
        lein) task_lein ;;
        *) task_all && exec zsh ;;
    esac
}

main "$@"
