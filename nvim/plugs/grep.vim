command! -nargs=+ GREP CtrlSF <args>

let g:ctrlsf_confirm_save = 0
let g:ctrlsf_position = 'bottom'
let g:ctrlsf_default_root = "project"
let g:ctrlsf_auto_focus = {
            \ "at": "start",
            \ }
let g:ctrlsf_mapping = {
    \ "quit": "<ESC>",
    \ "next": "<C-J>",
    \ "prev": "<C-K>",
    \ "openb": { "key": "o", "suffix": "<C-w>p" },
    \ }
