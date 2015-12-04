setlocal omnifunc=necoghc#omnifunc

setlocal nosmarttab

map <CR>hsk :cd ~/haskell-projects/<CR>
map <CR>hg  :!hoogle --count=15 "
map <CR>hl  :GhcModCheckAndLintAsync<CR>
map <CR>syn :SyntasticCheck<CR>
map <c-t> :GhcModType<CR>
map <c-c> :GhcModTypeClear<CR>

let g:syntastic_haskell_checkers = ['ghc_mod', 'hlint', 'scan']
let g:ghcmod_ghc_options = ['-fno-warn-orphans']
let g:necoghc_enable_detailed_browse = 1

"disable up/down
let g:ycm_key_list_select_completion = ['<TAB>']
let g:ycm_key_list_previous_completion = ['<S-TAB>']
