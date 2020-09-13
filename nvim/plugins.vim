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
Plug 'ntpeters/vim-better-whitespace'
Plug 'tpope/vim-repeat'
Plug 'tpope/vim-speeddating'
Plug 'tpope/vim-surround'
Plug 'mbbill/undotree'
Plug 'kshenoy/vim-signature' " Marks
Plug 'junegunn/vim-peekaboo' " Preview Registers
Plug 'RRethy/vim-illuminate' " Highlight cursor word matches
Plug 'mhinz/vim-signify' " git gutter
" }}}

" DIR/FILE VIEWER {{{
Plug 'romgrk/vimfiler-prompt'
Plug 'Shougo/vimfiler.vim'
" }}}

" SEARCH {{{
Plug 'dyng/ctrlsf.vim' " -> plugs/grep.vim
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
Plug 'rhysd/clever-f.vim'
" }}}

" THEME {{{
Plug 'KabbAmine/vCoolor.vim'
Plug 'joshdick/onedark.vim'
Plug 'norcalli/nvim-colorizer.lua'
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
Plug 'autozimu/LanguageClient-neovim', {'branch': 'next', 'do': 'bash install.sh'}
" }}}

" CLOJURE {{{
Plug 'Olical/conjure', {'for': 'clojure', 'tag': 'v4.3.1'}
Plug 'guns/vim-clojure-static', {'for': 'clojure'}
Plug 'guns/vim-sexp', {'for': ['clojure', 'fennel']}
Plug '~/dotfiles/lib/vim/conjure-highlight'
Plug 'luochen1990/rainbow'
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

let g:semicolon_which_key_map = get(g:, 'semicolon_which_key_map', {})

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

let g:semicolon_which_key_map.p = {
            \ 'name' : '+vim-plug',
            \ 'i' : [':e ~/dotfiles/nvim/plugins.vim | :source % | :PlugInstall', 'PlugInstall'],
            \ 'c' : [':e ~/dotfiles/nvim/plugins.vim | :source % | :PlugClean!', 'PlugClean!'],
            \ 'u' : [':e ~/dotfiles/nvim/plugins.vim | :source % | :PlugUpdate', 'PlugUpdate'],
            \ }

call which_key#register(';', "g:semicolon_which_key_map")
