"TODO FIXME
"let g:LanguageClient_settingsPath = ".lsp/settings.json"

let g:coc_global_extensions = ['coc-conjure']

set completeopt+=noinsert
set completeopt+=noselect
set completeopt-=preview

inoremap <silent><expr> <TAB>
      \ pumvisible() ? "\<C-n>" :
      \ <SID>check_back_space() ? "\<TAB>" :
      \ coc#refresh()
inoremap <expr><S-TAB> pumvisible() ? "\<C-p>" : "\<C-h>"

function! s:check_back_space() abort
  let col = col('.') - 1
  return !col || getline('.')[col - 1]  =~# '\s'
endfunction

" Make <CR> auto-select the first completion item and notify coc.nvim to
" format on enter, <cr> could be remapped by other vim plugin
inoremap <silent><expr> <cr> pumvisible() ? coc#_select_confirm()
                              \: "\<C-g>u\<CR>\<c-r>=coc#on_enter()\<CR>"

"call deoplete#custom#source('_', 'matchers', ['matcher_full_fuzzy'])

call SEMICOLON_GROUP('s', '+lsp')

call SEMICOLON_CMD('ss', ':CocRestart', 'restart')
call SEMICOLON_CMD('sa', ':CocAction', 'actions')
call SEMICOLON_CMD('sd', ':CocDiagnostics', 'diagnostics')
call SEMICOLON_CMD('sc', ':CocCommand', 'commands')
call SEMICOLON_CMD('so', ':CocOutline', 'outline')
call SEMICOLON_CMD('sg', ':CocOpenLog', 'debug log')
