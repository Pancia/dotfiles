function! VimLocalCWD()
    return $HOME . "/dotfiles/vimlocal/" . getcwd()
endfunction

function! VimLocalEdit()
    call mkdir(VimLocalCWD(), "p")
    execute "edit " . VimLocalCWD() . "/local.vim"
endfunction

silent! execute "source " . VimLocalCWD() . "/local.vim"

call WhichKey_GROUP('v', '+vim')
call WhichKey_CMD('vl', 'Open current vimlocal file', ':call VimLocalEdit()')
