let g:ale_linters = {
      \ 'clojure': ['copilot']
      \}

let g:ale_echo_msg_format = '[ALE:%linter%/%severity%]: %s'

nmap <silent> gen <Plug>(ale_next_wrap)
nmap <silent> gep <Plug>(ale_previous_wrap)

call SEMICOLON_GROUP('l', '+ALE linters')
call SEMICOLON_CMD('ln', ':normal <Plug>(ale_next_wrap)', 'Go to next message')
call SEMICOLON_CMD('lp', ':normal <Plug>(ale_previous_wrap)', 'Go to previous message')
call SEMICOLON_CMD('lr', ':ALEStopAllLSPs | :ALELint', 'Restart All Linters')
call SEMICOLON_CMD('lt', ':ALEToggle', 'Toggle Linting')
