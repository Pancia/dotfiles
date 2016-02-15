" AG {{{
let g:ag_working_path_mode="r"
" }}} AG

" AUTO_SAVE {{{
let g:auto_save=1
let g:auto_save_in_insert_mode=0
" }}} AUTO_SAVE

"DEOPLETE {{{
let g:deoplete#enable_at_startup = 1
inoremap <silent><expr> <Tab>
            \ pumvisible() ? "\<C-n>" :
            \ deoplete#mappings#manual_complete()
inoremap <silent><expr> <S-Tab>
		\ pumvisible() ? "\<C-p>" :
		\ deoplete#mappings#manual_complete()
"}}} DEOPLETE

" CTRLP {{{
let g:ctrlp_working_path_mode = 'ra'
let g:ctrlp_user_command = ['.git/', 'git --git-dir=%s/.git ls-files -oc --exclude-standard']
" }}} CTRLP

" CLJFMT {{{
let g:clj_fmt_autosave = 0
" }}} CLJFMT

" EASYMOTION {{{
"map <Space>  <Plug>(easymotion-prefix)
map <Space>j <Plug>(easymotion-j)
map <Space>k <Plug>(easymotion-k)
map <Space>s <Plug>(easymotion-s)
map //       <Plug>(easymotion-sn)
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
