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
Plug 'vimwiki/vimwiki', {'for': 'vimwiki'}
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
Plug 'ctrlpvim/ctrlp.vim'
Plug 'Shougo/unite.vim'
Plug 'Shougo/unite-help'
Plug 'Shougo/neoyank.vim'
Plug 'neoclide/coc.nvim', {'branch': 'release'}
" }}}

" CLOJURE {{{
Plug 'Olical/conjure', {'for': ['clojure', 'fennel'], 'tag': 'v4.18.0'}
Plug 'guns/vim-clojure-static', {'for': 'clojure'}
Plug 'guns/vim-sexp', {'for': ['clojure', 'fennel']}
Plug 'luochen1990/rainbow'
Plug '~/dotfiles/lib/vim/conjure-highlight'
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

" SEMICOLON WHICH KEY {{{
let g:semicolon_which_key_map = get(g:, 'semicolon_which_key_map', {})

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

function! WhichKey_CMD(path, name, cmd) abort
    call AssocIn(g:semicolon_which_key_map, split(a:path, '\zs'), [a:cmd, a:name])
endfunction

function! WhichKey_GROUP(path, name) abort
    call AssocIn(g:semicolon_which_key_map, split(a:path, '\zs')+['name'], a:name)
endfunction
" }}} SEMICOLON WHICH KEY

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

call WhichKey_GROUP('p', '+vim-plug')
call WhichKey_CMD('pi', 'PlugInstall', ':e ~/dotfiles/nvim/plugins.vim | :source % | :PlugInstall')
call WhichKey_CMD('pc', 'PlugClean!', ':e ~/dotfiles/nvim/plugins.vim | :source % | :PlugClean!')
call WhichKey_CMD('pu', 'PlugUpdate', ':e ~/dotfiles/nvim/plugins.vim | :source % | :PlugUpdate')
call WhichKey_CMD('po', 'open nvim/plugins.vim', ':e ~/dotfiles/nvim/plugins.vim')
call WhichKey_CMD('ps', 'PlugStatus', ':e ~/dotfiles/nvim/plugins.vim | :source % | :PlugStatus')
call WhichKey_CMD('pd', 'PlugDiff', ':e ~/dotfiles/nvim/plugins.vim | :source % | :PlugDiff')

call which_key#register(';', "g:semicolon_which_key_map")
