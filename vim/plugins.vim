call plug#begin('~/.vim/plugged')
" Essentials {{{
Plug 'vim-scripts/vim-auto-save'
Plug 'bling/vim-airline'
Plug 'christoomey/vim-tmux-navigator'
Plug 'kien/ctrlp.vim'
Plug 'sjl/gundo.vim'
Plug 'tpope/vim-repeat'
Plug 'scrooloose/syntastic'
Plug 'godlygeek/tabular'
Plug 'kien/rainbow_parentheses.vim'
Plug 'kshenoy/vim-signature'
Plug 'majutsushi/tagbar'
Plug 'ntpeters/vim-better-whitespace'
Plug 'takac/vim-spotifysearch'
Plug 'tpope/vim-dispatch'
Plug 'tpope/vim-projectionist'
Plug 'tpope/vim-speeddating'
Plug 'tpope/vim-surround'
Plug 'vim-scripts/Conque-Shell'
Plug 'vim-scripts/bufkill.vim'
" }}} Essentials
" {{{ Git
Plug 'tpope/vim-fugitive'
Plug 'rhysd/conflict-marker.vim'
" }}}
" Movement {{{
Plug 'Lokaltog/vim-easymotion'
Plug 'deris/vim-shot-f'
Plug 'Shougo/vimproc.vim',     { 'do' : 'make -f make_mac.mak' }
Plug 'shinokada/dragvisuals.vim'
" }}} Movement
" AutoComplete {{{
Plug 'Valloric/YouCompleteMe', { 'do' : 'git submodule update --init --recursive; ./install.sh --clang-completer' }
" }}} AutoComplete
" Clojure {{{
Plug 'guns/vim-clojure-static'
Plug 'guns/vim-clojure-highlight'
Plug 'guns/vim-sexp'
Plug 'tpope/vim-sexp-mappings-for-regular-people'
Plug 'tpope/vim-fireplace'
Plug 'clojure-emacs/cider-nrepl'
" }}} Clojure
" Haskell {{{
Plug 'dag/vim2hs',          { 'for' : 'haskell' }
Plug 'eagletmt/ghcmod-vim', { 'for' : 'haskell' }
Plug 'eagletmt/neco-ghc',   { 'for' : 'haskell' }
" }}} Haskell
" Elixir {{{
Plug 'elixir-lang/vim-elixir', { 'for' : 'elixir' }
" }}} Elixir
" Prolog {{{
Plug 'adimit/prolog.vim', { 'for' : 'prolog' }
" }}} Prolog
" JavaScript {{{
"Plug 'jelera/vim-javascript-syntax'
Plug 'digitaltoad/vim-jade'
Plug 'wavded/vim-stylus'
" }}} JavaScript
" Node.js {{{
Plug 'sidorares/node-vim-debugger'
Plug 'moll/vim-node'
Plug 'marijnh/tern_for_vim'
" }}} Node.js
call plug#end()
