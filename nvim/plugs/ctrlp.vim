let g:ctrlp_working_path_mode = 'ra'
let g:ctrlp_user_command = [ '.git', 'cd %s && cd `git rev-parse --show-toplevel` && git ls-files -co --exclude-standard' ]

let g:ctrlp_open_multiple_files = 'i'

let g:ctrlp_map = ''
let g:ctrlp_cmd = 'CtrlPMixed'
let g:ctrlp_mruf_relative = 1

let g:ctrlp_prompt_mappings = {
            \ 'PrtSelectMove("j")': ['<c-j>'],
            \ 'PrtSelectMove("k")': ['<c-k>'],
            \}
