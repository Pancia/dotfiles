" AUTO_SAVE {{{
let g:auto_save=1
let g:auto_save_in_insert_mode=0
" }}} AUTO_SAVE

" CTRLP {{{
let g:ctrlp_working_path_mode = 'ra'
let g:ctrlp_user_command = ['.git/', 'git --git-dir=%s/.git ls-files -oc --exclude-standard']
set wildignore+=*/target/*,*/dist/*,*/build/*,*/build/*,*.o
set wildignore+=*/.vim/autoload/*,*/.vim/bundle/*,*/.vim/plugged/*
set wildignore+=*/node_modules/*,*/resources/*/out/*,*/resources/public/js/*
set wildignore+=*/resources/public/cards/*
" }}} CTRLP

" EASYMOTION {{{
"map <Space>  <Plug>(easymotion-prefix)
map <Space>j <Plug>(easymotion-j)
map <Space>k <Plug>(easymotion-k)
map <Space>s <Plug>(easymotion-s)
map //       <Plug>(easymotion-sn)
" }}} EASYMOTION

" DRAGVISUALS {{{
vmap <expr> <LEFT>  DVB_Drag('left')
vmap <expr> <RIGHT> DVB_Drag('right')
vmap <expr> <DOWN>  DVB_Drag('down')
vmap <expr> <UP>    DVB_Drag('up')
vmap <expr> D       DVB_Duplicate()
" }}} DRAGVISUALS

" AIRLINE {{{
let g:airline#extensions#tabline#enabled=1
set laststatus=2 "Always show status line
" }}} AIRLINE

" SYNTASTIC {{{
set statusline+=%#warningmsg#
set statusline+=%{SyntasticStatuslineFlag()}
set statusline+=%*
let g:syntastic_always_populate_loc_list = 1
let g:syntastic_auto_loc_list = 1
let g:syntastic_check_on_open = 0
let g:syntastic_check_on_wq = 0
let g:syntastic_aggregate_errors = 1
let g:syntastic_mode_map = {
            \ "mode": "active",
            \ }
let g:syntastic_javascript_checkers = ['eslint']
let g:syntastic_json_checkers = ['jsonlint']
let g:syntastic_elixir_checkers = ['elixir']
let g:syntastic_enable_elixir_checker = 1
let g:syntastic_cpp_compiler = 'clang'
let g:syntastic_cpp_compiler_options = '-g -O0 -Wall -Wextra -Wpedantic -std=c++11'
augroup syntastic_plus_autosave
    au CursorHold,InsertLeave * nested update
augroup END
" }}} SYNTASTIC

" YOUCOMPLETEME {{{
let g:ycm_semantic_triggers = {'haskell' : ['.'], 'javascript' : ['.']}
" Helps with cpp and synastic
" - https://github.com/Valloric/YouCompleteMe#the-gycm_show_diagnostics_ui-option
let g:ycm_show_diagnostics_ui = 0
" Enables & configures semantic completion for c,c++...
let g:ycm_global_ycm_extra_conf = "~/.vim/.ycm_extra_conf.py"
let g:ycm_autoclose_preview_window_after_insertion = 1
" TODO: NOT WORKING, Disable arrow keys
let g:ycm_key_list_select_completion = ['<TAB>']
let g:ycm_key_list_previous_completion = ['<S-TAB>']
" }}} YOUCOMPLETEME

" TAGBAR {{{
let g:tagbar_left = 1
" }}} TAGBAR

" STRIP_WHITESPACE {{{
let g:strip_whitespace_on_save = 1
" }}} STRIP_WHITESPACE
