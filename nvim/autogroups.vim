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

" TASK: NOTE: CONTEXT: should all be TASK color
" NOTE:
" LANDMARK:
" CONTEXT:
" FOO: what is this?

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
