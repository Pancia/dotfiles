let g:sexp_filetypes = ""

augroup MY_VIM_SEXP_MAPPING
    autocmd!
    autocmd FileType clojure,fennel call s:my_vim_sexp_mappings()
augroup END

function! s:my_vim_sexp_mappings()
    xmap <buffer> af   <Plug>(sexp_outer_list)
    omap <buffer> af   <Plug>(sexp_outer_list)
    xmap <buffer> if   <Plug>(sexp_inner_list)
    omap <buffer> if   <Plug>(sexp_inner_list)
    xmap <buffer> aF   <Plug>(sexp_outer_top_list)
    omap <buffer> aF   <Plug>(sexp_outer_top_list)
    xmap <buffer> iF   <Plug>(sexp_inner_top_list)
    omap <buffer> iF   <Plug>(sexp_inner_top_list)
    xmap <buffer> as   <Plug>(sexp_outer_string)
    omap <buffer> as   <Plug>(sexp_outer_string)
    xmap <buffer> is   <Plug>(sexp_inner_string)
    omap <buffer> is   <Plug>(sexp_inner_string)
    xmap <buffer> ae   <Plug>(sexp_outer_element)
    omap <buffer> ae   <Plug>(sexp_outer_element)
    xmap <buffer> ie   <Plug>(sexp_inner_element)
    omap <buffer> ie   <Plug>(sexp_inner_element)

    nmap <buffer> si   <Plug>(sexp_round_head_wrap_list)
    xmap <buffer> si   <Plug>(sexp_round_head_wrap_list)
    nmap <buffer> sI   <Plug>(sexp_round_tail_wrap_list)
    xmap <buffer> sI   <Plug>(sexp_round_tail_wrap_list)
    nmap <buffer> s[   <Plug>(sexp_square_head_wrap_list)
    xmap <buffer> s[   <Plug>(sexp_square_head_wrap_list)
    nmap <buffer> s]   <Plug>(sexp_square_tail_wrap_list)
    xmap <buffer> s]   <Plug>(sexp_square_tail_wrap_list)
    nmap <buffer> s{   <Plug>(sexp_curly_head_wrap_list)
    xmap <buffer> s{   <Plug>(sexp_curly_head_wrap_list)
    nmap <buffer> s}   <Plug>(sexp_curly_tail_wrap_list)
    xmap <buffer> s}   <Plug>(sexp_curly_tail_wrap_list)
    nmap <buffer> sw   <Plug>(sexp_round_head_wrap_element)
    xmap <buffer> sw   <Plug>(sexp_round_head_wrap_element)
    nmap <buffer> sW   <Plug>(sexp_round_tail_wrap_element)
    xmap <buffer> sW   <Plug>(sexp_round_tail_wrap_element)
    nmap <buffer> se[  <Plug>(sexp_square_head_wrap_element)
    xmap <buffer> se[  <Plug>(sexp_square_head_wrap_element)
    nmap <buffer> se]  <Plug>(sexp_square_tail_wrap_element)
    xmap <buffer> se]  <Plug>(sexp_square_tail_wrap_element)
    nmap <buffer> se{  <Plug>(sexp_curly_head_wrap_element)
    xmap <buffer> se{  <Plug>(sexp_curly_head_wrap_element)
    nmap <buffer> se}  <Plug>(sexp_curly_tail_wrap_element)
    xmap <buffer> se}  <Plug>(sexp_curly_tail_wrap_element)
    nmap <buffer> s@   <Plug>(sexp_splice_list)
    nmap <buffer> s%   <Plug>(sexp_convolute)
    nmap <buffer> so   <Plug>(sexp_raise_list)
    xmap <buffer> so   <Plug>(sexp_raise_list)
    nmap <buffer> sO   <Plug>(sexp_raise_element)
    xmap <buffer> sO   <Plug>(sexp_raise_element)

    nnoremap <silent> s :<c-u>WhichKey       's'<CR>
    vnoremap <silent> s :<c-u>WhichKeyVisual 's'<CR>

    nmap <buffer> (    <Plug>(sexp_move_to_prev_bracket)
    xmap <buffer> (    <Plug>(sexp_move_to_prev_bracket)
    omap <buffer> (    <Plug>(sexp_move_to_prev_bracket)
    nmap <buffer> )    <Plug>(sexp_move_to_next_bracket)
    xmap <buffer> )    <Plug>(sexp_move_to_next_bracket)
    omap <buffer> )    <Plug>(sexp_move_to_next_bracket)
    nmap <buffer> [[   <Plug>(sexp_move_to_prev_top_element)
    xmap <buffer> [[   <Plug>(sexp_move_to_prev_top_element)
    omap <buffer> [[   <Plug>(sexp_move_to_prev_top_element)
    nmap <buffer> ]]   <Plug>(sexp_move_to_next_top_element)
    xmap <buffer> ]]   <Plug>(sexp_move_to_next_top_element)
    omap <buffer> ]]   <Plug>(sexp_move_to_next_top_element)
    nmap <buffer> [e   <Plug>(sexp_select_prev_element)
    xmap <buffer> [e   <Plug>(sexp_select_prev_element)
    omap <buffer> [e   <Plug>(sexp_select_prev_element)
    nmap <buffer> ]e   <Plug>(sexp_select_next_element)
    xmap <buffer> ]e   <Plug>(sexp_select_next_element)
    omap <buffer> ]e   <Plug>(sexp_select_next_element)

    nmap <buffer> B    <Plug>(sexp_move_to_prev_element_head)
    nmap <buffer> W    <Plug>(sexp_move_to_next_element_head)
    nmap <buffer> gE   <Plug>(sexp_move_to_prev_element_tail)
    nmap <buffer> E    <Plug>(sexp_move_to_next_element_tail)
    xmap <buffer> B    <Plug>(sexp_move_to_prev_element_head)
    xmap <buffer> W    <Plug>(sexp_move_to_next_element_head)
    xmap <buffer> gE   <Plug>(sexp_move_to_prev_element_tail)
    xmap <buffer> E    <Plug>(sexp_move_to_next_element_tail)
    omap <buffer> B    <Plug>(sexp_move_to_prev_element_head)
    omap <buffer> W    <Plug>(sexp_move_to_next_element_head)
    omap <buffer> gE   <Plug>(sexp_move_to_prev_element_tail)
    omap <buffer> E    <Plug>(sexp_move_to_next_element_tail)

    nmap <buffer> <I   <Plug>(sexp_insert_at_list_head)
    nmap <buffer> >I   <Plug>(sexp_insert_at_list_tail)
    nmap <buffer> <f   <Plug>(sexp_swap_list_backward)
    nmap <buffer> >f   <Plug>(sexp_swap_list_forward)
    nmap <buffer> <e   <Plug>(sexp_swap_element_backward)
    nmap <buffer> >e   <Plug>(sexp_swap_element_forward)
    nmap <buffer> >(   <Plug>(sexp_emit_head_element)
    nmap <buffer> <)   <Plug>(sexp_emit_tail_element)
    nmap <buffer> <(   <Plug>(sexp_capture_prev_element)
    nmap <buffer> >)   <Plug>(sexp_capture_next_element)

    if !exists("g:zprint_should_apply")
        nmap <buffer> ==   <Plug>(sexp_indent)
        nmap <buffer> =-   <Plug>(sexp_indent_top)
    else
        nnoremap <buffer> == :ZPRINT<CR>
        nnoremap <buffer> =- :ZPRINT<CR>
    endif

    imap <buffer> <BS> <Plug>(sexp_insert_backspace)
    imap <buffer> "    <Plug>(sexp_insert_double_quote)
    imap <buffer> (    <Plug>(sexp_insert_opening_round)
    imap <buffer> )    <Plug>(sexp_insert_closing_round)
    imap <buffer> [    <Plug>(sexp_insert_opening_square)
    imap <buffer> ]    <Plug>(sexp_insert_closing_square)
    imap <buffer> {    <Plug>(sexp_insert_opening_curly)
    imap <buffer> }    <Plug>(sexp_insert_closing_curly)

    call s:map_sexp_wrap('e', 'cseb', '(', ')', 0)
    call s:map_sexp_wrap('e', 'cse(', '(', ')', 0)
    call s:map_sexp_wrap('e', 'cse)', '(', ')', 1)
    call s:map_sexp_wrap('e', 'cse[', '[', ']', 0)
    call s:map_sexp_wrap('e', 'cse]', '[', ']', 1)
    call s:map_sexp_wrap('e', 'cse{', '{', '}', 0)
    call s:map_sexp_wrap('e', 'cse}', '{', '}', 1)
endfunction

function! s:map_sexp_wrap(type, target, left, right, pos)
    execute (a:type ==# 'v' ? 'x' : 'n').'noremap'
                \ '<buffer><silent>' a:target ':<C-U>let b:sexp_count = v:count<Bar>exe "normal! m`"<Bar>'
                \ . 'call sexp#wrap("'.a:type.'", "'.a:left.'", "'.a:right.'", '.a:pos.', 0)'
                \ . '<Bar>silent! call repeat#set("'.a:target.'", v:count)<CR>'
endfunction
