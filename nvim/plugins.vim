" auto-install vim-plug
if empty(glob('~/.config/nvim/autoload/plug.vim'))
    silent !curl -fLo ~/.config/nvim/autoload/plug.vim
                \ --create-dirs https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
    autocmd VimEnter * PlugInstall
endif
call plug#begin('~/.config/nvim/plugged')

" LIBS {{{
Plug 'Shougo/vimproc.vim', {'do' : 'make'}
Plug 'tpope/vim-dispatch'
" }}}

" ESSENTIALS {{{
Plug 'liuchengxu/vim-which-key'
Plug 'scrooloose/syntastic'
Plug 'godlygeek/tabular'
Plug 'majutsushi/tagbar'
Plug 'bling/vim-airline'
Plug 'vim-scripts/vim-auto-save'
Plug 'ntpeters/vim-better-whitespace'
Plug 'tpope/vim-repeat'
"Plug 'kshenoy/vim-signature' " Marks
Plug 'tpope/vim-speeddating'
Plug 'tpope/vim-surround'
Plug 'romgrk/vimfiler-prompt'
Plug 'Shougo/vimfiler.vim'
Plug 'mbbill/undotree'
" }}}

" WIKI {{{
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
" }}}

" AUTOCOMPLETE {{{
Plug 'Shougo/deoplete.nvim', { 'do': ':UpdateRemotePlugins' }
Plug 'ncm2/float-preview.nvim'
Plug 'Shougo/neco-syntax'
Plug 'Shougo/neco-vim'
Plug 'zchee/deoplete-zsh'
Plug 'ctrlpvim/ctrlp.vim'
Plug 'Shougo/unite.vim'
Plug 'Shougo/unite-help'
Plug 'Shougo/neoyank.vim'
" }}}

" CLOJURE {{{
Plug 'Olical/conjure', {'for': 'clojure', 'tag': 'v2.1.2', 'do': 'bin/compile' }
Plug 'guns/vim-clojure-highlight', {'for': 'clojure'}
Plug 'guns/vim-clojure-static', {'for': 'clojure'}
Plug 'guns/vim-sexp', {'for': 'clojure'}
Plug 'tpope/vim-sexp-mappings-for-regular-people', {'for': 'clojure'}
" }}}

" LUA {{{
"Plug 'xolox/vim-misc', {'for': 'lua'}
"Plug 'xolox/vim-lua-ftplugin', {'for': 'lua'}
" }}}

" RUBY {{{
Plug 'slim-template/vim-slim', {'for': 'ruby'}
" }}}

" GDScript {{{
Plug 'calviken/vim-gdscript3'
" }}}

call plug#end()
