let g:ale_linters = {
      \ 'clojure': ['clj-kondo', 'copilot']
      \}

let g:ale_echo_msg_format = '[%linter%/%severity%]: %s'

nmap <silent> gen <Plug>(ale_next_wrap)
nmap <silent> gep <Plug>(ale_previous_wrap)

call WhichKey_GROUP('l', '+ALE linters')
call WhichKey_CMD('ln', 'Go to next message', ':normal <Plug>(ale_next_wrap)')
call WhichKey_CMD('lp', 'Go to previous message', ':normal <Plug>(ale_previous_wrap)')
call WhichKey_CMD('lr', 'Restart All Linters', ':ALEStopAllLSPs | :ALELint')
call WhichKey_CMD('lt', 'Toggle Linting', ':ALEToggle')
