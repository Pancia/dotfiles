let g:vimwiki_list = [
            \{'path': '~/Dropbox/wiki', 'path_html': '~/Dropbox/wiki', 'auto_tags': 1, 'auto_export': 1 },
            \{'path': '~/dotfiles/wiki', 'auto_tags': 1, 'ext': '.wiki' }
            \]

let g:vimwiki_global_ext = 0
let g:vimwiki_map_prefix = ',w'

function! VimwikiLinkHandler(link)
    " Use Vim to open external files with the 'vfile:' scheme.  E.g.:
    "   1) [[vfile:~/Code/PythonProject/abc123.py]]
    "   2) [[vfile:./|Wiki Home]]
    let link = a:link
    if link =~# '^vfile:'
        let link = link[1:]
    else
        return 0
    endif
    let link_infos = vimwiki#base#resolve_link(link)
    if link_infos.filename == ''
        echomsg 'Vimwiki Error: Unable to resolve link!'
        return 0
    else
        exe 'edit ' . fnameescape(link_infos.filename)
        return 1
    endif
endfunction
