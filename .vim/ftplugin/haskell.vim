setlocal omnifunc=necoghc#omnifunc

"haskell
map <cr>hsk :cd ~/haskell-projects/<cr>
map <cr>hg  :!hoogle --count=15 "
map <cr>hl  :GhcModCheckAndLintAsync<cr>
map <c-t> :GhcModType<cr>
if exists(":GhcModTypeClear")
    map <c-c> :GhcModTypeClear<cr>
endif
let g:syntastic_haskell_checkers = ['ghc_mod', 'hlint', 'scan']
let g:ghcmod_ghc_options = ['-fno-warn-orphans']
let g:necoghc_enable_detailed_browse = 1
