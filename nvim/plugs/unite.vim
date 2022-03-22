let g:unite_source_history_yank_enable=1

nnoremap \ :WhichKey '\'<CR>
call which_key#register('\', "g:unite_which_key_map")
let g:unite_which_key_map = {
            \ 'name' : '+unite' ,
            \ ' ' : [':Unite source', '#source'],
            \ 'p' : [':Unite history/yank', '#yank #paste'],
            \ 'u' : [':UndotreeToggle', 'UndoTree'],
            \ 'y' : [':Unite history/yank', '#yank #paste'],
            \ }

autocmd FileType unite call s:unite_settings()
function! s:unite_settings()
    imap <buffer> <C-j> <Plug>(unite_select_next_line)
    imap <buffer> <C-k> <Plug>(unite_select_previous_line)
    nmap <buffer> <ESC> <Plug>(unite_all_exit)
endfunction

call unite#custom#profile('default', 'context', {
            \   'start_insert': 1,
            \   'winheight': 15,
            \   'direction': 'botright',
            \ })

if executable('ag')
    let g:unite_source_grep_command = 'ag'
    let g:unite_source_grep_default_opts = '--vimgrep --nocolor'
    let g:unite_source_grep_recursive_opt = ''
endif

call unite#filters#matcher_default#use(['matcher_fuzzy'])
