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
Plug 'vim-airline/vim-airline' " Status Bar
Plug 'ntpeters/vim-better-whitespace'
Plug 'tpope/vim-repeat'
Plug 'tpope/vim-speeddating'
Plug 'tpope/vim-surround'
Plug 'mbbill/undotree'
Plug 'kshenoy/vim-signature' " Marks
Plug 'junegunn/vim-peekaboo' " Preview Registers
Plug 'RRethy/vim-illuminate' " Highlight cursor word matches
Plug 'airblade/vim-gitgutter'
Plug 'junegunn/vim-easy-align'
" }}}

" DIR/FILE VIEWER {{{
Plug 'romgrk/vimfiler-prompt'
Plug 'Shougo/vimfiler.vim'
" }}}

" SEARCH {{{
Plug 'dyng/ctrlsf.vim' " -> plugs/grep.vim
" }}}

" WIKI {{{
Plug 'junegunn/fzf', { 'do': { -> fzf#install() } }
Plug 'junegunn/fzf.vim'
Plug 'vimwiki/vimwiki'
" }}}

" {{{ GIT
Plug 'rhysd/conflict-marker.vim'
Plug 'tpope/vim-fugitive'
" }}}

" MOVEMENT {{{
Plug 'Lokaltog/vim-easymotion'
" }}}

" THEME {{{
Plug 'KabbAmine/vCoolor.vim'
Plug 'joshdick/onedark.vim'
Plug 'norcalli/nvim-colorizer.lua'
" }}}

" AUTOCOMPLETE {{{
Plug 'ncm2/float-preview.nvim'
Plug 'Shougo/neco-syntax'
Plug 'Shougo/neco-vim'
Plug 'Shougo/unite.vim'
Plug 'Shougo/unite-help'
Plug 'Shougo/neoyank.vim'
" }}}

" LSP {{{
Plug 'neovim/nvim-lspconfig'
Plug 'gfanto/fzf-lsp.nvim'
Plug 'hrsh7th/cmp-nvim-lsp'
Plug 'hrsh7th/cmp-buffer'
Plug 'hrsh7th/cmp-path'
Plug 'hrsh7th/cmp-cmdline'
Plug 'hrsh7th/nvim-cmp'
" }}}

" CLOJURE {{{
Plug 'Olical/conjure', {'for': ['clojure', 'fennel'], 'tag': 'v4.30.1'}
Plug 'guns/vim-clojure-static', {'for': 'clojure'}
Plug 'guns/vim-sexp', {'for': ['clojure', 'fennel']}
Plug 'luochen1990/rainbow'
Plug '~/projects/work/copilot/editor-plugins/vim'
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

function! AssocIn(dict, key, value) abort
    if a:key == []
        if string(a:dict) !~ '{}' && string(a:dict) !=# string(a:value)
            echoerr "WARNING: overriding existing value ".string(a:dict)." with ".string(a:value)
        endif
        return a:value
    elseif has_key(a:dict, a:key[0])
        let a:dict[a:key[0]] = AssocIn(a:dict[a:key[0]], a:key[1:], a:value)
    else
        let a:dict[a:key[0]] = AssocIn({}, a:key[1:], a:value)
    endif
    return a:dict
endfunction

" SEMICOLON WHICH KEY {{{
let g:semicolon_which_key_map = get(g:, 'semicolon_which_key_map', {})

call which_key#register(';', "g:semicolon_which_key_map")

function! SEMICOLON_CMD(path, cmd, ...) abort
    let tag = a:0 >= 1 ? a:1 : a:cmd
    call AssocIn(g:semicolon_which_key_map, split(a:path, '\zs'), [a:cmd, l:tag])
endfunction

function! SEMICOLON_GROUP(path, name) abort
    call AssocIn(g:semicolon_which_key_map, split(a:path, '\zs')+['name'], a:name)
endfunction
" }}} SEMICOLON WHICH KEY

" COMMA WHICH KEY {{{
let g:comma_which_key_map = get(g:, 'comma_which_key_map', {})

call which_key#register(',', "g:comma_which_key_map")

function! COMMA_CMD(path, cmd, ...) abort
    let tag = a:0 >= 1 ? a:1 : a:cmd
    call AssocIn(g:comma_which_key_map, split(a:path, '\zs'), [a:cmd, l:tag])
endfunction

function! COMMA_GROUP(path, name) abort
    call AssocIn(g:comma_which_key_map, split(a:path, '\zs')+['name'], a:name)
endfunction
" }}} COMMA WHICH KEY

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

call SEMICOLON_GROUP('p', '+vim-plug')
call SEMICOLON_CMD('pi', ':e ~/dotfiles/nvim/plugins.vim | :source % | :PlugInstall', 'PlugInstall')
call SEMICOLON_CMD('pc', ':e ~/dotfiles/nvim/plugins.vim | :source % | :PlugClean!', 'PlugClean!')
call SEMICOLON_CMD('pu', ':e ~/dotfiles/nvim/plugins.vim | :source % | :PlugUpdate', 'PlugUpdate')
call SEMICOLON_CMD('po', ':e ~/dotfiles/nvim/plugins.vim', 'open nvim/plugins.vim')
call SEMICOLON_CMD('ps', ':e ~/dotfiles/nvim/plugins.vim | :source % | :PlugStatus', 'PlugStatus')
call SEMICOLON_CMD('pd', ':e ~/dotfiles/nvim/plugins.vim | :source % | :PlugDiff', 'PlugDiff')
