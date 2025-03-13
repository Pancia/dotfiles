" Disable arrows
noremap <up> <nop>
inoremap <up> <nop>
noremap <down> <nop>
inoremap <down> <nop>
noremap <left> <nop>
noremap <right> <nop>
noremap <CR> <nop>
" Map Y to y$, makes way more sense
noremap Y y$
" U redoes
nnoremap U <c-r>
" ctrl-e removes last search highlighting
nnoremap <silent> <c-e> /reset\.search<CR>:nohlsearch<CR>
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
if !exists('g:vscode')
  nmap <c-k> :bnext<CR>
  nmap <c-j> :bprevious<CR>
endif
command! BD b#|bd#
" terminal helpers
tnoremap <expr> <Esc> (&filetype == "fzf") ? "<Esc>" : "<C-\><C-n>"
nnoremap ! :!
