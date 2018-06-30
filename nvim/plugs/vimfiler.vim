let g:vimfiler_as_default_explorer = 1
nnoremap gy :YcmCompleter GoTo<CR>

augroup VIMFILER
    au!
    au FileType vimfiler nmap <buffer> i :VimFilerPrompt<cr>
    au FileType vimfiler nmap <buffer> q <Plug>(vimfiler_exit)
augroup END
