set nocompatible
call plug#begin('~/.vim/plugged')

"Essentials
Plug 'vim-scripts/vim-auto-save'
Plug 'bling/vim-airline'
Plug 'christoomey/vim-tmux-navigator'
Plug 'kien/ctrlp.vim'
Plug 'sjl/gundo.vim'
Plug 'tpope/vim-repeat'
Plug 'scrooloose/syntastic'

"Movement
Plug 'Lokaltog/vim-easymotion'
Plug 'deris/vim-shot-f'
Plug 'Shougo/vimproc.vim',     { 'do' : 'make' }

"AutoComplete
Plug 'Valloric/YouCompleteMe', { 'do' : 'git submodule update --init --recursive; ./install.sh' }

Plug 'godlygeek/tabular'
Plug 'honza/vim-snippets'
Plug 'kien/rainbow_parentheses.vim'
Plug 'majutsushi/tagbar'
Plug 'mileszs/ack.vim'
Plug 'ntpeters/vim-better-whitespace'
Plug 'sirver/ultisnips'
Plug 'takac/vim-spotifysearch'
Plug 'tpope/vim-dispatch'
Plug 'tpope/vim-fugitive'
Plug 'tpope/vim-projectionist'
Plug 'tpope/vim-speeddating'
Plug 'tpope/vim-surround'

"Clojure
Plug 'guns/vim-clojure-static',    { 'for' : 'clojure' }
Plug 'guns/vim-clojure-highlight', { 'for' : 'clojure' }
Plug 'tpope/vim-leiningen',        { 'for' : 'clojure' }
Plug 'guns/vim-sexp',              { 'for' : 'clojure' }
"Lag caused by vim-fireplace
"Plug 'clojure-emacs/cider-nrepl', { 'for' : 'clojure' }
"Plug 'tpope/vim-fireplace',       { 'for' : 'clojure' }
Plug 'tpope/vim-sexp-mappings-for-regular-people', { 'for' : 'clojure' }

"Haskell
Plug 'dag/vim2hs',          { 'for' : 'haskell' }
Plug 'eagletmt/ghcmod-vim', { 'for' : 'haskell' }
Plug 'eagletmt/neco-ghc',   { 'for' : 'haskell' }

"Elixir
Plug 'elixir-lang/vim-elixir', { 'for' : 'elixir' }

"Prolog
Plug 'adimit/prolog.vim', { 'for' : 'prolog' }

call plug#end()

map <cr>vim :e ~/.vimrc<cr>
map <cr>pi  :PlugInstall<cr>
map <cr>pc  :PlugClean<cr>
map <cr>so  :so %<cr>

filetype plugin indent on

".loki -~> .clj
au BufNewFile,BufRead *.loki set filetype=clojure

augroup rainbowParens
    au!
    au VimEnter * RainbowParenthesesToggle
    au Syntax * RainbowParenthesesLoadRound
    au Syntax * RainbowParenthesesLoadSquare
    au Syntax * RainbowParenthesesLoadBraces
augroup END

augroup essentials
    au!
    "wrap at col=80
    autocmd FileType text setlocal textwidth=80
    "On open buffer, go to last spot
    autocmd BufReadPost *
                \ if line("'\"") > 1 && line("'\"") <= line("$") |
                \   exe "normal! g`\"" |
                \ endif
augroup END
