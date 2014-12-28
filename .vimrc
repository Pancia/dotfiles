call plug#begin('~/.vim/plugged')

"TODO: Lag might be caused by
"utl|SyntaxRange|sexp*|NrrwRgn|tagbar|orgmode&co...

Plug 'Lokaltog/vim-easymotion'
Plug 'Shougo/vimproc.vim', { 'do' : 'make' }
Plug 'Valloric/YouCompleteMe', { 'do' : 'git submodule update --init --recursive; ./install.sh' }
Plug 'bling/vim-airline'
Plug 'christoomey/vim-tmux-navigator'
Plug 'junegunn/vim-easy-align'
Plug 'kien/ctrlp.vim'
Plug 'kien/rainbow_parentheses.vim'
Plug 'majutsushi/tagbar'
Plug 'mileszs/ack.vim'
Plug 'ntpeters/vim-better-whitespace'
Plug 'sjl/gundo.vim'
Plug 'takac/vim-spotifysearch'
Plug 'tpope/vim-dispatch'
Plug 'tpope/vim-fugitive'
Plug 'tpope/vim-projectionist'
Plug 'tpope/vim-repeat'
Plug 'tpope/vim-speeddating'
Plug 'tpope/vim-surround'
Plug 'vim-scripts/vim-auto-save'

Plug 'itchyny/calendar.vim', { 'for' : 'org' }
Plug 'jceb/vim-orgmode', { 'for' : 'org' }
Plug 'vim-scripts/SyntaxRange', { 'for' : 'org' }
Plug 'vim-scripts/utl.vim', { 'for' : 'org' }

"Plug 'clojure-emacs/cider-nrepl', { 'for' : 'clojure' }
Plug 'guns/vim-clojure-static', { 'for' : 'clojure' }
"Plug 'tpope/vim-fireplace', { 'for' : 'clojure' }

Plug 'guns/vim-clojure-highlight', { 'for' : 'clojure' }
Plug 'tpope/vim-leiningen', { 'for' : 'clojure' }
Plug 'guns/vim-sexp', { 'for' : 'clojure' }
Plug 'tpope/vim-sexp-mappings-for-regular-people', { 'for' : 'clojure' }

Plug 'dag/vim2hs', { 'for' : 'haskell' }
Plug 'eagletmt/ghcmod-vim', { 'for' : 'haskell' }
Plug 'eagletmt/neco-ghc', { 'for' : 'haskell' }
Plug 'bitc/vim-hdevtools', { 'for' : 'haskell' }

call plug#end()
set nocompatible

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
map <BS>   <c-o>
map <S-BS> <c-i>

map _        <Plug>(easymotion-prefix)
map <Space>j <Plug>(easymotion-j)
map <Space>k <Plug>(easymotion-k)
map <Space>s <Plug>(easymotion-s)
map //       <Plug>(easymotion-sn)

map ˚ :bnext<cr>
map ∆ :bprevious<cr>

map <cr>u   :GundoToggle<cr>
map <cr>dc  :cd ~/dunjeon-crawler/<cr>
map <cr>ss  :SpotifySearch
map <cr>sh  :ConqueTerm bash<cr>
map <cr>tb  :TagbarToggle<cr>

map <cr>org :e ~/Dropbox/org/todo.org<cr>

map <cr>vim :e ~/.vimrc<cr>
map <cr>pi  :PlugInstall<cr>
map <cr>pc  :PlugClean<cr>
map <cr>so  :so %<cr>

map <cr>hsk :cd ~/haskell-projects/<cr>
map <cr>hg  :!hoogle --count=15 "
map <cr>hl  :GhcModCheckAndLintAsync

vmap <Space>a <Plug>(EasyAlign)
nmap <Space>a <Plug>(EasyAlign)

let g:paredit_shortmaps=0
let g:airline_detect_whitespace=0
set wildignore+=*/target/*
let g:auto_save=1
let g:ctrlp_by_filename=1
let g:airline#extensions#tabline#enabled=1
let g:auto_save_in_insert_mode=0

highlight ColorColumn ctermbg=magenta
call matchadd('ColorColumn', '\%121v', 100)

set backspace=indent,eol,start
set nobackup
set history=100
set ruler
set showcmd
set incsearch
set nu
set hlsearch

set noswapfile
set tabstop=4
set shiftwidth=4
set expandtab
set guifont=Menlo\ Regular:h22
set visualbell
set foldmethod=indent

colorscheme darkblue
colorscheme macvim
syntax on
hi folded guibg=#707070

if has("autocmd")

  filetype plugin indent on
  autocmd BufRead,BufNewFile *.cc filetype indent off

  augroup vimrcEx
  au!

  au VimEnter * RainbowParenthesesToggle
  au Syntax * RainbowParenthesesLoadRound
  au Syntax * RainbowParenthesesLoadSquare
  au Syntax * RainbowParenthesesLoadBraces

  autocmd FileType text setlocal textwidth=80

  autocmd BufReadPost *
    \ if line("'\"") > 1 && line("'\"") <= line("$") |
    \   exe "normal! g`\"" |
    \ endif

  augroup END

else

  set autoindent

endif

