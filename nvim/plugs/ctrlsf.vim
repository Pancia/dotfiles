let g:ctrlsf_confirm_save = 0
let g:ctrlsf_default_root = "project"
let g:ctrlsf_auto_focus = {
            \ "at": "done",
            \ "duration_less_than": 5000,
            \ }
let g:ctrlsf_mapping = {
    \ "quit": "<esc>",
    \ }
cnoreabbrev Grep CtrlSF
