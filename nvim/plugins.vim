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
Plug 'huiyiqun/elvish.vim'
" }}}

" WIKI {{{
Plug 'gokcehan/vim-opex'
let g:vimwiki_map_prefix = ','
Plug 'vimwiki/vimwiki'
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
Plug 'clojure-vim/async-clj-omni'
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
Plug 'clojure-emacs/cider-nrepl'
Plug 'venantius/vim-cljfmt'
Plug 'guns/vim-clojure-highlight'
Plug 'guns/vim-clojure-static'
Plug 'tpope/vim-fireplace'
Plug 'guns/vim-sexp'
Plug 'tpope/vim-sexp-mappings-for-regular-people'
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
Plug 'wavded/vim-stylus'
Plug 'digitaltoad/vim-jade'
"Plug 'jelera/vim-javascript-syntax'
" }}}

" NODE.JS {{{
Plug 'sidorares/node-vim-debugger'
Plug 'moll/vim-node'
" }}}

" LUX {{{
Plug 'mwgkgk/lux-vim'
" }}}

" RUST {{{
Plug 'rust-lang/rust.vim'
Plug 'rhysd/rust-doc.vim'
" }}}

" ANDROID/KOTLIN/JAVA {{{
Plug 'udalov/kotlin-vim'
Plug 'hsanson/vim-android'
Plug 'artur-shaik/vim-javacomplete2'
" }}}

call plug#end()
