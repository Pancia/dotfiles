function! SetCursorToLastKnownPosition()
    if &filetype !~ 'git\|commit\c'
        if line("'\"") > 1 && line("'\"") <= line("$")
            exe "normal! g`\""
        endif
    endif
endfunction

augroup Essentials
    au!
    au FileType text setlocal textwidth=80
    au BufReadPost * call SetCursorToLastKnownPosition()
    au FileType vim setlocal foldmethod=marker
    au BufEnter * silent! lcd %:p:h " Eqv to `set autochdir`
    au FileType help map <buffer> q :q<cr>
    au FileType man map <buffer> q :bd<cr>
    au FileType vimfiler nmap <buffer> i :VimFilerPrompt<cr>
    au FileType vimfiler nmap <buffer> q <Plug>(vimfiler_exit)
    au BufNewFile,BufRead TODL setlocal formatoptions-=cro
augroup END

augroup RainbowParens
    au!
    let rp_blacklist = ['javascript']
    au VimEnter * if index(rp_blacklist, &ft) < 0 | RainbowParenthesesToggle
    au Syntax * if index(rp_blacklist, &ft) < 0 | RainbowParenthesesLoadRound
    au Syntax * if index(rp_blacklist, &ft) < 0 | RainbowParenthesesLoadSquare
    au Syntax * if index(rp_blacklist, &ft) < 0 | RainbowParenthesesLoadBraces
augroup END

augroup FileTypes
    au BufNewFile,BufRead .eslintrc set filetype=json
    au BufNewFile,BufRead *.boot set filetype=clojure
augroup END

augroup Terminal
    au TermOpen * set bufhidden=hide
    au TermOpen * redraw
augroup END

augroup KOTLIN
    au!
    au FileType kotlin setlocal omnifunc=javacomplete#Complete
augroup END

augroup JAVA
    au!
    au FileType java setlocal omnifunc=javacomplete#Complete
    function! FindConfig(what)
        silent! lcd %:p:h
        return findfile(a:what, expand('%:p:h') . ';')
    endfunction
    au FileType java let g:syntastic_java_javac_config_file = FindConfig('.syntastic_javac_config')
augroup END
