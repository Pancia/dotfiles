function! VimLocalCWD()
    return $HOME . "/dotfiles/vimlocal/" . getcwd()
endfunction

function! VimLocalEdit()
    call mkdir(VimLocalCWD(), "p")
    execute "edit " . VimLocalCWD() . "/local.vim"
endfunction

silent! execute "source " . VimLocalCWD() . "/local.vim"

call SEMICOLON_GROUP('v', '+vim')
call SEMICOLON_CMD('vl', ':call VimLocalEdit()', 'Open current vimlocal file')

