" https://github.com/Shougo/deoplete.nvim/wiki/Completion-Sources
let g:deoplete#enable_at_startup = 1
let g:deoplete#enable_smart_case = 1
" https://github.com/Shougo/deoplete.nvim/blob/master/doc/deoplete.txt
inoremap <expr> <Tab> pumvisible() ? "\<C-n>" : "\<Tab>"
inoremap <expr> <S-Tab> pumvisible() ? "\<C-p>" : "\<S-Tab>"
let g:deoplete#keyword_patterns = {}
let g:deoplete#keyword_patterns.clojure = '[\w!$%&*+/:<=>?@\^_~\-\.#]*'
call deoplete#custom#option('omni_patterns', {
            \ 'java': '[^. *\t]\.\w*',
            \ 'kotlin': '[^. *\t]\.\w*',
            \})
