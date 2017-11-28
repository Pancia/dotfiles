" AG {{{
let g:ag_working_path_mode="r"
" }}} AG

" AUTO_SAVE {{{
let g:auto_save=1
let g:auto_save_in_insert_mode=0
" }}} AUTO_SAVE

" CTRLP {{{
let g:ctrlp_working_path_mode = 'ra'
let g:ctrlp_user_command = ['.git/', 'git --git-dir=%s/.git ls-files -oc --exclude-standard']
" }}} CTRLP

" UNITE {{{
source ~/dotfiles/nvim/unite-config.vim
" }}} UNITE

" vimfiler {{{
let g:vimfiler_as_default_explorer = 1
nnoremap gy :YcmCompleter GoTo<CR>
" }}}

" CLJFMT {{{
let g:clj_fmt_autosave = 0
" }}} CLJFMT

" EASYMOTION {{{
map <Space> <Plug>(easymotion-prefix)
map /       <Plug>(easymotion-sn)
" }}} EASYMOTION

" AIRLINE {{{
let g:airline#extensions#tabline#enabled=1
set laststatus=2 "Always show status line
" }}} AIRLINE

" TAGBAR {{{
let g:tagbar_left = 1
" }}} TAGBAR

" STRIP_WHITESPACE {{{
let g:strip_whitespace_on_save = 1
" }}} STRIP_WHITESPACE

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
" }}} RAINBOW_PARENS

" YOUCOMPLETEME {{{
let g:ycm_semantic_triggers = {'haskell' : ['.'], 'javascript' : ['.']}
" Helps with cpp and synastic
" - https://github.com/Valloric/YouCompleteMe#the-gycm_show_diagnostics_ui-option
let g:ycm_show_diagnostics_ui = 0
" Enables & configures semantic completion for c,c++...
let g:ycm_autoclose_preview_window_after_insertion = 1
" TODO: NOT WORKING, Disable arrow keys
let g:ycm_key_list_select_completion = ['<TAB>']
let g:ycm_key_list_previous_completion = ['<S-TAB>']
" }}} YOUCOMPLETEME

" JAVA {{{
let g:syntastic_java_checkers=['javac']
let g:syntastic_java_javac_config_file_enabled = 1
" }}}
