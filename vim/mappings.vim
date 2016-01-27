" Disable arrows
nmap <up> <nop>
nmap <down> <nop>
nmap <left> <nop>
nmap <right> <nop>
nmap <Space> <nop>
nmap <CR> <nop>
" Leader mappings
let mapleader = "<Space>"
map s \
map <Space><Space> \
" Swap j,k with gj,gk
noremap j gj
noremap k gk
noremap gj j
noremap gk k
" map Q to gQ, which is a more useful `q:`
noremap Q gQ
" U redoes
nnoremap U <c-r>
" ctrl-e removes last search highlighting
nnoremap <c-e> /reset\.search<CR>:nohlsearch<CR>
" Use BS to navigate cursor history
nmap <BS>   <c-o>zz
nmap <S-BS> <c-i>zz
" Center screen when searching
nnoremap n nzz
nnoremap N Nzz
nnoremap * *zz
nnoremap # #zz
nnoremap g* g*zz
nnoremap g# g#zz
" alt: {j :bp, k :bn, h :tabp, l :tabn}
map ˚ :bnext<CR>zz
map ∆ :bprevious<CR>zz
map ˙ :tabp<CR>zz
map ¬ :tabn<CR>zz
" Enter.+ mappings
map <CR>pi   :PlugInstall<CR>
map <CR>pc   :PlugInPlugClean<CR>
map <CR>bsh  :e ~/dotfiles/bashrc<CR>
map <CR>vim  :e ~/dotfiles/vimrc<CR>:cd ~/dotfiles/vim<CR>
map <CR>lein :e ~/.lein/profiles.clj<CR>:cd ~/.lein<CR>
map <CR>so   :so %<CR>
map <CR>u    :GundoToggle<CR>
map <CR>tb   :TagbarToggle<CR>
map <CR>bda  :bd *<CR>
map <CR>tidy :g/^\s\+[\)\]\}]/normal kJ<CR>
command! Tidy g/^\s\+[\)\]\}]/normal kJ<CR>
