" Disable arrows
nmap <up> <nop>
let g:which_key_map['<Up>'] = 'which_key_ignore'
nmap <down> <nop>
let g:which_key_map['<Down>'] = 'which_key_ignore'
nmap <left> <nop>
let g:which_key_map['<Left>'] = 'which_key_ignore'
nmap <right> <nop>
let g:which_key_map['<Right>'] = 'which_key_ignore'
nmap <CR> <nop>
let g:which_key_map['<CR>'] = 'which_key_ignore'
" Map Y to y$, makes way more sense
map Y y$
" Swap j,k with gj,gk
noremap j gj
noremap k gk
noremap gj j
let g:which_key_map['gj'] = 'which_key_ignore'
noremap gk k
let g:which_key_map['gk'] = 'which_key_ignore'
" U redoes
nnoremap U <c-r>
" ctrl-e removes last search highlighting
nnoremap <c-e> /reset\.search<CR>:nohlsearch<CR>
let g:which_key_map['<C-E>'] = 'which_key_ignore'
" Use BS to navigate cursor history
noremap <BS>   <c-o>zz
let g:which_key_map['<BS>'] = 'which_key_ignore'
noremap <S-BS> <c-i>zz
let g:which_key_map['<S-BS>'] = 'which_key_ignore'
" Center screen when searching
nnoremap n nzz
let g:which_key_map.n = 'which_key_ignore'
nnoremap N Nzz
let g:which_key_map.N = 'which_key_ignore'
nnoremap * *zz
let g:which_key_map['*'] = 'which_key_ignore'
nnoremap # #zz
let g:which_key_map['#'] = 'which_key_ignore'
nnoremap g* g*zz
let g:which_key_map.g['*'] = 'which_key_ignore'
nnoremap g# g#zz
let g:which_key_map.g['#'] = 'which_key_ignore'
" buffer nav
nmap <c-k> :bnext<CR>
let g:which_key_map['<C-K>'] = 'which_key_ignore'
nmap <c-j> :bprevious<CR>
let g:which_key_map['<C-J>'] = 'which_key_ignore'
command! BD b#|bd#
" terminal helpers
tnoremap <Esc> <C-\><C-n>
