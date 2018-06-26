" auto-install vim-plug
if empty(glob('~/.config/nvim/autoload/plug.vim'))
    silent !curl -fLo ~/.config/nvim/autoload/plug.vim --create-dirs https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
    autocmd VimEnter * PlugInstall
endif
call plug#begin('~/.config/nvim/plugged')

" ESSENTIALS {{{
Plug 'Shougo/vimfiler.vim'
Plug 'romgrk/vimfiler-prompt'
Plug 'Shougo/vimproc.vim', {'do' : 'make'}
Plug 'bling/vim-airline'
Plug 'godlygeek/tabular'
"Plug 'kshenoy/vim-signature' " Marks
Plug 'majutsushi/tagbar'
Plug 'ntpeters/vim-better-whitespace'
Plug 'rking/ag.vim'
Plug 'scrooloose/syntastic'
Plug 'sjl/gundo.vim'
Plug 'tpope/vim-dispatch'
Plug 'tpope/vim-projectionist'
Plug 'tpope/vim-repeat'
Plug 'tpope/vim-speeddating'
Plug 'tpope/vim-surround'
Plug 'vim-scripts/bufkill.vim'
Plug 'vim-scripts/vim-auto-save'
" }}}
" {{{ GIT
Plug 'tpope/vim-fugitive'
Plug 'rhysd/conflict-marker.vim'
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
Plug 'Shougo/deoplete.nvim', { 'do': ':UpdateRemotePlugins' }
Plug 'ctrlpvim/ctrlp.vim'
Plug 'Shougo/unite.vim'
Plug 'Shougo/neoyank.vim'
Plug 'Shougo/unite-help'
" }}}
" CLOJURE {{{
Plug 'guns/vim-clojure-static'
Plug 'guns/vim-clojure-highlight'
Plug 'guns/vim-sexp'
Plug 'tpope/vim-sexp-mappings-for-regular-people'
Plug 'tpope/vim-fireplace'
Plug 'clojure-emacs/cider-nrepl'
Plug 'venantius/vim-cljfmt'
" }}}
" HASKELL {{{
Plug 'dag/vim2hs',          { 'for' : 'haskell' }
Plug 'eagletmt/ghcmod-vim', { 'for' : 'haskell' }
Plug 'eagletmt/neco-ghc',   { 'for' : 'haskell' }
" }}}
" ELIXIR {{{
Plug 'elixir-lang/vim-elixir', { 'for' : 'elixir' }
" }}}
" PROLOG {{{
Plug 'adimit/prolog.vim', { 'for' : 'prolog' }
" }}}
" JAVASCRIPT {{{
"Plug 'jelera/vim-javascript-syntax'
Plug 'digitaltoad/vim-jade'
Plug 'wavded/vim-stylus'
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
