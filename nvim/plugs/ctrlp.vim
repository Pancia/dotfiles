let g:ctrlp_working_path_mode = 'ra'
let g:ctrlp_user_command = [ '.git', 'cd %s && cd `git rev-parse --show-toplevel` && git ls-files -co --exclude-standard' ]

let g:ctrlp_cmd = 'CtrlPMixed'
let g:ctrlp_mruf_relative = 1

nmap <C-R> :CtrlPBuffer<CR>
nmap <C-T> :CtrlPTag<CR>
