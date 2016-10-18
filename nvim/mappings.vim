" Disable arrows
nmap <up> <nop>
nmap <down> <nop>
nmap <left> <nop>
nmap <right> <nop>
nmap <CR> <nop>
" Leader mappings
let mapleader = "<Space>"
map s \
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
" <space>^2 mappings
nmap <space><space>pi   :PlugInstall<CR>
nmap <space><space>pc   :PlugClean<CR>
nmap <space><space>zsh  :e ~/dotfiles/zsh<CR>
nmap <space><space>vim  :e ~/dotfiles/nvim/init.vim<CR>:cd ~/dotfiles/nvim<CR>
nmap <space><space>lein :e ~/.lein/profiles.clj<CR>:cd ~/.lein<CR>
nmap <space><space>so   :so %<CR>
nmap <space><space>u    :GundoToggle<CR>
nmap <space><space>tb   :TagbarToggle<CR>
nmap <space><space>bda  :bd *<CR>
nmap <space><space>tidy :g/^\s\+[\)\]\}]/normal kJ<CR>
command! Tidy g/^\s\+[\)\]\}]/normal kJ<CR>

tnoremap <Esc> <C-\><C-n>
