set runtimepath+=~/dotfiles/nvim/lua/

source ~/dotfiles/nvim/plugins.vim
source ~/dotfiles/nvim/autogroups.vim
source ~/dotfiles/nvim/mappings.vim
source ~/dotfiles/nvim/settings.vim
if !exists('g:vscode')
    source ~/dotfiles/nvim/theme.vim
    source ~/dotfiles/nvim/syntax.vim
else
endif

source ~/dotfiles/nvim/local.vim

source ~/dotfiles/nvim/init.lua
