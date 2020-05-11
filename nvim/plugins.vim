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
Plug 'w0rp/ale' "Async Lint Engine
Plug 'bling/vim-airline' " Status Bar
Plug 'vim-scripts/vim-auto-save'
Plug 'ntpeters/vim-better-whitespace'
Plug 'tpope/vim-repeat'
Plug 'tpope/vim-speeddating'
Plug 'tpope/vim-surround'
Plug 'mbbill/undotree'
Plug 'kshenoy/vim-signature' " Marks
Plug 'junegunn/vim-peekaboo' " Preview Registers
Plug 'RRethy/vim-illuminate' " Highlight cursor word matches
Plug 'airblade/vim-gitgutter'
" }}}

" DIR/FILE VIEWER {{{
Plug 'romgrk/vimfiler-prompt'
Plug 'Shougo/vimfiler.vim'
" }}}

" SEARCH {{{
Plug 'dyng/ctrlsf.vim'
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
" }}}

" LUA {{{
"Plug 'xolox/vim-misc', {'for': 'lua'}
"Plug 'xolox/vim-lua-ftplugin', {'for': 'lua'}
Plug 'bakpakin/fennel.vim'
" }}}

" RUBY {{{
Plug 'slim-template/vim-slim', {'for': 'ruby'}
" }}}

" GDScript {{{
Plug 'calviken/vim-gdscript3'
" }}}

call plug#end()

let g:unite_source_menu_menus = get(g:, 'unite_source_menu_menus', {})

for plug_conf in split(globpath(expand("<sfile>:p:h"), 'plugs/*.vim'), '\n')
    execute 'source ' . plug_conf
endfor

for ftp in split(globpath('~/dotfiles/nvim/ftplugin', '*.vim'), '\n')
    let base_ftp = fnamemodify(ftp,":t")
    let dest_ftp = expand('~/.config/nvim/ftplugin/'.base_ftp)
    if !filereadable(dest_ftp)
        call system('echo "source ~/dotfiles/nvim/ftplugin/'.base_ftp.'" > '.dest_ftp)
    endif
endfor
