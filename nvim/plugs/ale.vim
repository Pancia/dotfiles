let g:ale_linters = {
      \ 'clojure': ['clj-kondo', 'guardrails']
      \}

let g:ale_echo_msg_format = '[%linter%/%severity%]: %s'

nmap <silent> gen <Plug>(ale_next_wrap)
nmap <silent> gep <Plug>(ale_previous_wrap)

let g:semicolon_which_key_map.l = {
            \ 'name' : '+ALE Linters',
            \ 'r' : [':ALEStopAllLSPs | :ALELint', 'Restart All Linters'],
            \ 'n' : [':normal <Plug>(ale_next_wrap)', 'Go to next message'],
            \ 'p' : [':normal <Plug>(ale_previous_wrap)', 'Go to previous message'],
            \ }
