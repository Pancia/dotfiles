nnoremap ; :WhichKey ';'<CR>
let g:semicolon_which_key_map['%'] = [':source ~/dotfiles/nvim/init.vim', '> source vimrc']
let g:semicolon_which_key_map['d'] = {
            \   'name' : '+dotfiles',
            \   'v' : [':e ~/dotfiles/nvim/init.vim | cd ~/dotfiles/nvim', '> vimrc dotfiles'],
            \   'z' : [':e ~/dotfiles/zsh/init.zsh | cd ~/dotfiles/zsh', '> zshrc dotfiles'],
            \ }
let g:semicolon_which_key_map['b'] = {
            \   'name' : '+buffers',
            \   'D' : [':%bd', '> delete all buffers'],
            \   'd' : [':bd', '> delete this buffer'],
            \   'b' : [':b# | :bd#', '> delete buffer and go to last buffer (without closing window)'],
            \ }
