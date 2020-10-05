nnoremap ; :WhichKey ';'<CR>
call WhichKey_CMD('%', 'source vimrc', ':source ~/dotfiles/nvim/init.vim')

call WhichKey_GROUP('d', '+dotfiles')
call WhichKey_CMD('dv', 'vimrc dotfiles', ':e ~/dotfiles/nvim/init.vim | cd ~/dotfiles/nvim')
call WhichKey_CMD('dz', 'edit zshrc init', ':cd ~/dotfiles/zsh | edit init.zsh')
call WhichKey_CMD('dZ', 'edit zshrc', ':cd ~/dotfiles/zsh | edit zshrc')

call WhichKey_GROUP('b', '+dotfiles')
call WhichKey_CMD('bD', 'delete all buffers', ':%bd')
call WhichKey_CMD('bd', 'delete this buffer', ':bd')
call WhichKey_CMD('bb', 'delete buffer and go to last buffer (without closing window)', ':b# | :bd#')
