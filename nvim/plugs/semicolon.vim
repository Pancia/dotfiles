nnoremap ; :WhichKey ';'<CR>
call SEMICOLON_CMD('%', ':source ~/dotfiles/nvim/init.vim', 'source vimrc')

call SEMICOLON_GROUP('d', '+dotfiles')
call SEMICOLON_CMD('dv', ':e ~/dotfiles/nvim/init.vim | cd ~/dotfiles/nvim', 'vimrc dotfiles')
call SEMICOLON_CMD('df', ':cd ~/dotfiles/fish | edit config.fish', 'edit fish config')
call SEMICOLON_CMD('dF', ':cd ~/dotfiles/fish/functions', 'edit fish functions')

call SEMICOLON_GROUP('b', '+buffers')
call SEMICOLON_CMD('bD', ':%bd', 'delete all buffers')
call SEMICOLON_CMD('bd', ':bd', 'delete this buffer')
call SEMICOLON_CMD('bb', ':b# | :bd#', 'delete buffer and go to last buffer (without closing window)')

call SEMICOLON_GROUP('s', '+session')
call SEMICOLON_CMD('ss', ':SessionSave', 'save session')
call SEMICOLON_CMD('sl', ':SessionLoad', 'load session')
call SEMICOLON_CMD('sq', ':SessionQuit', 'save and quit')
call SEMICOLON_CMD('sr', ':SessionRestart', 'save and restart')

