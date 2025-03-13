if !exists('g:vscode')
    function! VimLocalCWD()
    else
        return $HOME . "/dotfiles/vimlocal/" . getcwd()
    endfunction

    function! VimLocalEdit()
        call mkdir(VimLocalCWD(), "p")
        execute "edit " . VimLocalCWD() . "/local.vim"
    endfunction

    silent! execute "source " . VimLocalCWD() . "/local.vim"

    call SEMICOLON_GROUP('v', '+vim(local)')
    call SEMICOLON_CMD('vl', 'VimLocalEdit()', 'Open current vimlocal file')
endif
