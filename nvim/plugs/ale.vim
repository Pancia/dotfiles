let g:ale_linters = {
      \ 'clojure': ['clj-kondo']
      \}

let g:ale_echo_msg_format = '[%linter%/%severity%]: %s'

nmap <silent> gep <Plug>(ale_previous_wrap)
nmap <silent> gen <Plug>(ale_next_wrap)
