nmap <up> <nop>
nmap <down> <nop>
nmap <left> <nop>
nmap <right> <nop>
nmap <Space> <nop>

let mapleader = "<Space>"
map s \
map <Space><Space> \

noremap j gj
noremap k gk
noremap gj j
noremap gk k

noremap Q gQ

nnoremap U <c-r>
nnoremap <c-r> :nohlsearch<CR>

nmap <BS>   <c-o>
nmap <S-BS> <c-i>

nnoremap zoo zO
nnoremap zcc zC

"Center screen when searching
nnoremap n nzz
nnoremap N Nzz
nnoremap * *zz
nnoremap # #zz
nnoremap g* g*zz
nnoremap g# g#zz

"alt: {j :bp, k :bn, h :tabp, l :tabn}
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
