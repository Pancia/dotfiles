" https://github.com/Shougo/deoplete.nvim/wiki/Completion-Sources
let g:deoplete#enable_at_startup = 1
call deoplete#custom#option({
            \ 'smart_case': v:true,
            \ 'keyword_patterns': {'clojure': '[\w!$%&*+/:<=>?@\^_~\-\.#]*'},
            \})

call deoplete#custom#source('_', 'matchers', ['matcher_full_fuzzy'])

set completeopt+=noinsert

" https://github.com/Shougo/deoplete.nvim/blob/master/doc/deoplete.txt
inoremap <expr> <Tab> pumvisible() ? "\<C-n>" : "\<Tab>"
inoremap <expr> <S-Tab> pumvisible() ? "\<C-p>" : "\<S-Tab>"

set completeopt+=noselect
inoremap <silent> <CR> <C-r>=<SID>my_cr_function()<CR>
function! s:my_cr_function() abort
    return deoplete#close_popup() . "\<CR>"
endfunction

" https://github.com/Shougo/deoplete.nvim/issues/115
autocmd InsertLeave,CompleteDone * if pumvisible() == 0 | silent! pclose | endif

" USE FLOAT PREVIEW INSTEAD
set completeopt-=preview
let g:float_preview#docked = 0
let g:float_preview#max_width = 120
let g:float_preview#max_height = 60
