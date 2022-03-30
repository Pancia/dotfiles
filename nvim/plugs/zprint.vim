" Based off: https://github.com/fatih/vim-go/tree/6866d086ff3492060832a204feb5b8a3dd2777e5
" Copyright (c) 2015, Fatih Arslan
" License file: https://github.com/fatih/vim-go/blob/0ff2a642c4353da6316fac42f2cc2ce2f536ef9f/LICENSE
" Based off: https://github.com/bfontaine/zprint.vim/blob/master/autoload/zprint.vim
" License file: https://github.com/bfontaine/zprint.vim/blob/master/LICENSE

" save vi compatibility settings
let s:cpo_save = &cpo
set cpo&vim

function zprint#apply()
    let l:fname = fnamemodify(expand("%"), ':p:gs?\\?/?')
    let l:curw = winsaveview()
    let l:tmpfile = tempname() . '.zprint'
    let current_col = col('.')
    let l:cmd = 'zprint < ' . l:fname . ' > ' . l:tmpfile
    let l:out = system(l:cmd)
    let diff_offset = len(readfile(l:tmpfile)) - line('$')
    if v:shell_error
        echomsg l:out
    else
        call zprint#update_file(l:tmpfile, l:fname)
    endif
    call delete(l:tmpfile)
    call winrestview(l:curw)
    call cursor(line('.') + diff_offset, current_col)
    syntax sync fromstart
endfunction

function! zprint#update_file(source, target)
    call writefile(readfile(a:source), a:target)
    " reload buffer to reflect latest changes
    silent edit!
    let &syntax = &syntax
endfunction

" restore vi compatibility settings
let &cpo = s:cpo_save
unlet s:cpo_save
