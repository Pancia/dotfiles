" Disable arrows
nmap <up> <nop>
nmap <down> <nop>
nmap <left> <nop>
nmap <right> <nop>
nmap <CR> <nop>
" Map Y to y$, makes way more sense
map Y y$
" Leader mappings
let mapleader = "<Space>"
map s \
" Swap j,k with gj,gk
noremap j gj
noremap k gk
noremap gj j
noremap gk k
" U redoes
nnoremap U <c-r>
" ctrl-e removes last search highlighting
nnoremap <c-e> /reset\.search<CR>:nohlsearch<CR>
" Use BS to navigate cursor history
noremap <BS>   <c-o>zz
noremap <S-BS> <c-i>zz
" Center screen when searching
nnoremap n nzz
nnoremap N Nzz
nnoremap * *zz
nnoremap # #zz
nnoremap g* g*zz
nnoremap g# g#zz
" buffer nav
nmap <c-k> :bnext<CR>
nmap <c-j> :bprevious<CR>
command! BD b#|bd#
" terminal helpers
tnoremap <Esc> <C-\><C-n>
