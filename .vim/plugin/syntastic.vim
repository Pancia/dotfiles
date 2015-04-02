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

let g:syntastic_cpp_compiler = 'clang'
let g:syntastic_cpp_compiler_options = '-g -O0 -Wall -Wextra -Wpedantic -std=c++11'

augroup syntastic_plus_autosave
    au CursorHold,InsertLeave * nested update
augroup END
