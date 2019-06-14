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
    au BufNewFile,BufRead .eslintrc set filetype=json
    au BufNewFile,BufRead TODO set filetype=zsh
    au BufNewFile,BufRead *.svelte set filetype=html
    au BufNewFile,BufRead *.wiki set filetype=vimwiki
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
