nmap <up> <nop>
nmap <down> <nop>
nmap <left> <nop>
nmap <right> <nop>
nmap <Space> <nop>
nmap <CR> <nop>
nmap <BS> <nop>

let mapleader = "<Space>"
map s \
map <Space><Space> \

map j gj
map k gk
map Q gQ

nnoremap U <c-r>
nnoremap <c-r> <nop>
map <BS>   <c-o>
map <S-BS> <c-i>

map ˚ :bnext<cr>
map ∆ :bprevious<cr>
map ˙ :tabp<cr>
map ¬ :tabn<cr>

map <cr>u   :GundoToggle<cr>
map <cr>dc  :cd ~/dunjeon-crawler/<cr>
map <cr>ss  :SpotifySearch
map <cr>sh  :ConqueTerm bash<cr>
map <cr>tb  :TagbarToggle<cr>
if !exists(":Bda")
    command Bda 1,99bdelete
    map <cr>bd :Bda<cr>
endif
