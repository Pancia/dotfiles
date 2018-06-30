function! SetCursorToLastKnownPosition()
    if &filetype !~ 'git\|commit\c'
        if line("'\"") > 1 && line("'\"") <= line("$")
            exe "normal! g`\""
        endif
    endif
endfunction

augroup Essentials
    au!
    au BufReadPost * call SetCursorToLastKnownPosition()
    au BufEnter * silent! lcd %:p:h " Eqv to `set autochdir`
augroup END

augroup FileTypes
    au!
    au BufNewFile,BufRead TODL setlocal formatoptions-=cro
    au BufNewFile,BufRead .eslintrc set filetype=json
augroup END

augroup Terminal
    au!
    au TermOpen * setlocal bufhidden=hide
    autocmd BufLeave term://* if len(get(b:, 'term_title', ''))
                \| execute 'file '
                \. matchstr(expand('<afile>'), 'term://(.{-}//(\d+:)?)?\ze.*')
                \. escape('term://'.b:terminal_job_pid.'/'.b:term_title, ' ')
                \| endif
    au TermOpen * redraw
augroup END
