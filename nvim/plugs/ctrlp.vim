let g:ctrlp_working_path_mode = 'ra'
let g:ctrlp_user_command = [ '.git', 'cd %s && cd `git rev-parse --show-toplevel` && git ls-files -co --exclude-standard' ]
noremap <C-R> :CtrlPBuffer<CR>
nmap <C-t> :CtrlPTag<CR>
