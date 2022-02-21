nnoremap ; :WhichKey ';'<CR>
call SEMICOLON_CMD('%', ':source ~/dotfiles/nvim/init.vim', 'source vimrc')

call SEMICOLON_GROUP('d', '+dotfiles')
call SEMICOLON_CMD('dv', ':e ~/dotfiles/nvim/init.vim | cd ~/dotfiles/nvim', 'vimrc dotfiles')
call SEMICOLON_CMD('dz', ':cd ~/dotfiles/zsh | edit init.zsh', 'edit zshrc init')
call SEMICOLON_CMD('dZ', ':cd ~/dotfiles/zsh | edit zshrc', 'edit zshrc')

call SEMICOLON_GROUP('b', '+dotfiles')
call SEMICOLON_CMD('bD', ':%bd', 'delete all buffers')
call SEMICOLON_CMD('bd', ':bd', 'delete this buffer')
call SEMICOLON_CMD('bb', ':b# | :bd#', 'delete buffer and go to last buffer (without closing window)')

