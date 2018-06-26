" AG {{{
let g:ag_working_path_mode="r"
" }}}

" VIM-AUTO-SAVE {{{
let g:auto_save=1
let g:auto_save_in_insert_mode=0
" }}}

" CTRLP {{{
let g:ctrlp_working_path_mode = 'ra'
let g:ctrlp_user_command = [ '.git', 'cd %s && cd `git rev-parse --show-toplevel` && git ls-files -co --exclude-standard' ]
" }}}

" UNITE {{{
source ~/dotfiles/nvim/unite-config.vim
" }}}

" VIMFILER {{{
let g:vimfiler_as_default_explorer = 1
nnoremap gy :YcmCompleter GoTo<CR>
" }}}

" CLJFMT {{{
let g:clj_fmt_autosave = 0
" }}}

" EASYMOTION {{{
map <Space> <Plug>(easymotion-prefix)
map /       <Plug>(easymotion-sn)
" }}}

" AIRLINE {{{
let g:airline#extensions#tabline#enabled=1
set laststatus=2 "Always show status line
" }}}

" TAGBAR {{{
let g:tagbar_left = 1
" }}}

" STRIP_WHITESPACE {{{
let g:strip_whitespace_on_save = 1
" }}}

" RAINBOW_PARENS {{{
let g:rbpt_max = 32
let g:rbpt_colorpairs = [
    \ ['brown',       'RoyalBlue3'],
    \ ['Darkblue',    'SeaGreen3'],
    \ ['darkgray',    'DarkOrchid3'],
    \ ['darkgreen',   'firebrick3'],
    \ ['darkcyan',    'RoyalBlue3'],
    \ ['darkred',     'SeaGreen3'],
    \ ['darkmagenta', 'DarkOrchid3'],
    \ ['brown',       'firebrick3'],
    \ ['gray',        'RoyalBlue3'],
    \ ['darkmagenta', 'DarkOrchid3'],
    \ ['Darkblue',    'firebrick3'],
    \ ['darkgreen',   'RoyalBlue3'],
    \ ['darkcyan',    'SeaGreen3'],
    \ ['darkred',     'DarkOrchid3'],
    \ ['red',         'firebrick3'],
    \ ]
" }}}

" DEOPLETE {{{
" https://github.com/Shougo/deoplete.nvim/wiki/Completion-Sources
let g:deoplete#enable_at_startup = 1
let g:deoplete#enable_smart_case = 1
" https://github.com/Shougo/deoplete.nvim/blob/master/doc/deoplete.txt
inoremap <expr> <Tab> pumvisible() ? "\<C-n>" : "\<Tab>"
inoremap <expr> <S-Tab> pumvisible() ? "\<C-p>" : "\<S-Tab>"

" }}}

" ANDROID/JAVA {{{
let g:android_sdk_path = '/Users/Anthony/Library/Android/sdk'
call deoplete#custom#option('omni_patterns', {
            \ 'java': '[^. *\t]\.\w*',
            \ 'kotlin': '[^. *\t]\.\w*',
            \})
"}}}

" RUST {{{
let g:rustfmt_autosave = 1
let g:syntastic_rust_checkers = ['cargo']
let g:ycm_rust_src_path = '$HOME/.rustup/toolchains/stable-x86_64-apple-darwin/lib/rustlib/src/rust/src/'
let g:rust_doc#downloaded_rust_doc_dir = '~/.rustup/toolchains/stable-x86_64-apple-darwin'
" }}}
