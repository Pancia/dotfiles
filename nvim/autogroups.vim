function! SetCursorToLastKnownPosition()
    let [line,column] = searchpos("RESUMEHERE")
    if l:line !~ 0
        "escape, go to line, go to column 0 then go right l:column times
        call feedkeys("\<C-\>\<C-n>".l:line."G0".(l:column-1)."l", 'n')
    elseif &filetype !~ '' && &filetype !~ 'git\|help\|commit\c'
        if line("'\"") > 1 && line("'\"") <= line("$")
            exe "normal! g`\""
        endif
    endif
endfunction

augroup Essentials
    au!
    au BufEnter * call SetCursorToLastKnownPosition()
    au BufEnter * silent! lcd %:p:h " Eqv to `set autochdir`
augroup END

" Bit me in the ass as it remembers mappings by default
" should not so I can change plugin config & have it fully update
let &viewoptions="cursor,folds"
augroup RememberFolds
  autocmd!
  autocmd BufWinLeave * silent! mkview
  autocmd BufWinEnter * silent! loadview
augroup END

augroup FileTypes
    au!
    au BufRead *.wiki set filetype=vimwiki
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

set updatetime=200

function NotFiles()
    if bufname('') =~ 'conjure-log-\d\+.cljc'
        set buftype=nofile
        set wrap
    endif
endfunction

augroup not_files
  autocmd!
  au BufEnter * call NotFiles()
augroup END

function! AutoSave()
    if bufname('') !~ 'conjure-log-\d\+.cljc'
        let was_modified = &modified
        silent! wa
        if was_modified && !&modified
            echo "(AutoSaved at " . strftime("%H:%M:%S") . ")"
        endif
    endif
endfunction

augroup auto_save
  autocmd!
  au CursorHold,InsertLeave,TextChanged * nested call AutoSave()
augroup END
