let g:vimfiler_as_default_explorer = 1
call vimfiler#custom#profile('default', 'context', {
            \ 'force_quit' : 1,
            \ })

augroup VIMFILER
    au!
    au FileType vimfiler nmap <buffer> i :VimFilerPrompt<cr>
    au FileType vimfiler nmap <buffer> <esc> <Plug>(vimfiler_exit)
    au FileType vimfiler unmap <buffer> <c-j>
augroup END
