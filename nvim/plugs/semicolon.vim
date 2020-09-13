nnoremap ; :WhichKey ';'<CR>
let g:semicolon_which_key_map = {
            \ '%' : [':source ~/dotfiles/nvim/init.vim', '> source vimrc'],
            \ 'd' : {
            \   'name' : '+dotfiles',
            \   'v' : [':e ~/dotfiles/nvim/init.vim | cd ~/dotfiles/nvim', '> vimrc dotfiles'],
            \   'z' : [':e ~/dotfiles/zsh/init.zsh | cd ~/dotfiles/zsh', '> zshrc dotfiles'],
            \ },
            \ 'b' : {
            \   'name' : '+buffers',
            \   'D' : [':%bd', '> delete all buffers'],
            \ },
            \}
