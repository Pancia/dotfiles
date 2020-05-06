let g:ctrlp_working_path_mode = 'ra'
let g:ctrlp_user_command = [ '.git', 'cd %s && cd `git rev-parse --show-toplevel` && git ls-files -co --exclude-standard' ]

let g:ctrlp_cmd = 'CtrlPMixed'
let g:ctrlp_mruf_relative = 1
let g:which_key_map['<C-P>'] = 'which_key_ignore'

nmap <C-R> :CtrlPBuffer<CR>
let g:which_key_map['<C-R>'] = 'which_key_ignore'
nmap <C-T> :CtrlPTag<CR>
let g:which_key_map['<C-T>'] = 'which_key_ignore'
