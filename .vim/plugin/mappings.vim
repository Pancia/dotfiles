nmap <up> <nop>
nmap <down> <nop>
nmap <left> <nop>
nmap <right> <nop>
nmap <Space> <nop>

let mapleader = "<Space>"
map s \
map <Space><Space> \

map j gj
map k gk
map Q gQ

nnoremap U <c-r>
nnoremap <c-r> <nop>
map <c-r> :nohlsearch<CR>

nmap <BS>   <c-o>
nmap <S-BS> <c-i>

map ˚ :bnext<CR>
map ∆ :bprevious<CR>
map ˙ :tabp<CR>
map ¬ :tabn<CR>

map <CR>u   :GundoToggle<CR>
map <CR>dc  :cd ~/dunjeon-crawler/<CR>
map <CR>ss  :SpotifySearch<space>
map <CR>tb  :TagbarToggle<CR>
if !exists(":Bda")
    command Bda 1,99bdelete
    map <CR>bda :Bda<CR>
endif
