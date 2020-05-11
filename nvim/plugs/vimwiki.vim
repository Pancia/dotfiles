let g:vimwiki_list = [
            \{'path': '~/Dropbox/wiki', 'path_html': '~/Dropbox/wiki', 'auto_tags': 1, 'auto_export': 1 },
            \{'path': '~/dotfiles/wiki', 'auto_tags': 1 }
            \]

let g:vimwiki_map_prefix = ','

let g:unite_source_menu_menus.wiki = {'description' : 'Vimwiki helpers'}
let g:unite_source_menu_menus.wiki.command_candidates = [
            \['Vimwiki Index', 'VimwikiIndex'],
            \['Vimwiki TabIndex', 'VimwikiTabIndex'],
            \['Vimwiki UISelect', 'VimwikiUISelect'],
            \['Vimwiki DiaryIndex', 'VimwikiDiaryIndex'],
            \['Vimwiki MakeDiaryNote', 'VimwikiMakeDiaryNote'],
            \['Vimwiki TabMakeDiaryNote', 'VimwikiTabMakeDiaryNote'],
            \['Vimwiki MakeYesterdayDiaryNote', 'VimwikiMakeYesterdayDiaryNote'],
            \['Vimwiki MakeTomorrowDiaryNote', 'VimwikiMakeTomorrowDiaryNote'],
            \['Vimwiki 2HTML', 'Vimwiki2HTML'],
            \['Vimwiki 2HTMLBrowse', 'Vimwiki2HTMLBrowse'],
            \['Vimwiki DiaryGenerateLinks', 'VimwikiDiaryGenerateLinks'],
            \['Vimwiki FollowLink', 'VimwikiFollowLink'],
            \['Vimwiki SplitLink', 'VimwikiSplitLink'],
            \['Vimwiki VSplitLink', 'VimwikiVSplitLink'],
            \['Vimwiki TabnewLink', 'VimwikiTabnewLink'],
            \['Vimwiki DeleteLink', 'VimwikiDeleteLink'],
            \['Vimwiki RenameLink', 'VimwikiRenameLink'],
            \]

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
