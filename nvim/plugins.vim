" auto-install vim-plug
if empty(glob('~/.config/nvim/autoload/plug.vim'))
    silent !curl -fLo ~/.config/nvim/autoload/plug.vim
                \ --create-dirs https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
    autocmd VimEnter * PlugInstall
endif
call plug#begin('~/.config/nvim/plugged')

" ESSENTIALS {{{
Plug 'rking/ag.vim'
Plug 'vim-scripts/bufkill.vim'
Plug 'sjl/gundo.vim'
Plug 'scrooloose/syntastic'
Plug 'godlygeek/tabular'
Plug 'majutsushi/tagbar'
Plug 'bling/vim-airline'
Plug 'vim-scripts/vim-auto-save'
Plug 'ntpeters/vim-better-whitespace'
Plug 'tpope/vim-dispatch'
Plug 'tpope/vim-projectionist'
Plug 'tpope/vim-repeat'
"Plug 'kshenoy/vim-signature' " Marks
Plug 'tpope/vim-speeddating'
Plug 'tpope/vim-surround'
Plug 'romgrk/vimfiler-prompt'
Plug 'Shougo/vimfiler.vim'
Plug 'Shougo/vimproc.vim', {'do' : 'make'}
" }}}

" SHELL {{{
Plug 'huiyiqun/elvish.vim', {'for': 'elvish'}
" }}}

" WIKI {{{
Plug 'gokcehan/vim-opex'
let g:vimwiki_map_prefix = ','
Plug 'vimwiki/vimwiki', {'for': 'vimwiki'}
" }}}

" {{{ GIT
Plug 'rhysd/conflict-marker.vim'
Plug 'tpope/vim-fugitive'
" }}}

" MOVEMENT {{{
Plug 'Lokaltog/vim-easymotion'
Plug 'deris/vim-shot-f'
" }}}

" THEME {{{
Plug 'joshdick/onedark.vim'
Plug 'kien/rainbow_parentheses.vim'
" }}}

" AUTOCOMPLETE {{{
Plug 'clojure-vim/async-clj-omni', {'for': 'clojure'}
Plug 'ctrlpvim/ctrlp.vim'
Plug 'zchee/deoplete-zsh'
Plug 'Shougo/deoplete.nvim', { 'do': ':UpdateRemotePlugins' }
Plug 'Shougo/neco-syntax'
Plug 'Shougo/neco-vim'
Plug 'Shougo/neoyank.vim'
Plug 'Shougo/unite-help'
Plug 'Shougo/unite.vim'
" }}}

" CLOJURE {{{
Plug 'clojure-emacs/cider-nrepl', {'for': 'clojure'}
Plug 'venantius/vim-cljfmt', {'for': 'clojure'}
Plug 'guns/vim-clojure-highlight', {'for': 'clojure'}
Plug 'guns/vim-clojure-static', {'for': 'clojure'}
Plug 'tpope/vim-fireplace', {'for': 'clojure'}
Plug 'guns/vim-sexp', {'for': 'clojure'}
Plug 'tpope/vim-sexp-mappings-for-regular-people', {'for': 'clojure'}
" }}}

" HASKELL {{{
Plug 'eagletmt/ghcmod-vim', { 'for' : 'haskell' }
Plug 'eagletmt/neco-ghc',   { 'for' : 'haskell' }
Plug 'dag/vim2hs',          { 'for' : 'haskell' }
" }}}

" ELIXIR {{{
Plug 'elixir-lang/vim-elixir', { 'for' : 'elixir' }
" }}}

" PROLOG {{{
Plug 'adimit/prolog.vim', { 'for' : 'prolog' }
" }}}

" JAVASCRIPT {{{
Plug 'wavded/vim-stylus', {'for': 'javascript'}
Plug 'digitaltoad/vim-jade', {'for': 'javascript'}
"Plug 'jelera/vim-javascript-syntax'
" }}}

" NODE.JS {{{
Plug 'sidorares/node-vim-debugger', {'for': 'javascript'}
Plug 'moll/vim-node', {'for': 'javascript'}
" }}}

" LUX {{{
Plug 'mwgkgk/lux-vim', {'for': 'lux'}
" }}}

" RUST {{{
Plug 'rust-lang/rust.vim', {'for': 'rust'}
Plug 'rhysd/rust-doc.vim', {'for': 'rust'}
" }}}

" ANDROID/KOTLIN/JAVA {{{
Plug 'udalov/kotlin-vim', {'for': 'kotlin'}
Plug 'hsanson/vim-android', {'for': 'kotlin'}
Plug 'artur-shaik/vim-javacomplete2', {'for': 'kotlin'}
" }}}

" LUA {{{
Plug 'xolox/vim-misc', {'for': 'lua'}
Plug 'xolox/vim-lua-ftplugin', {'for': 'lua'}
" }}}

" RUBY {{{
Plug 'slim-template/vim-slim', {'for': 'ruby'}
" }}}

call plug#end()
