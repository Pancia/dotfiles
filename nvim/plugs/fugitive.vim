let g:unite_source_menu_menus.git = {'description' : 'fugitive commands'}
let g:unite_source_menu_menus.git.command_candidates = [
            \['> git status', 'Gstatus'],
            \['> git diff', 'Gdiff'],
            \['> git commit', 'Gcommit'],
            \['> git log', 'exe "silent Glog | Unite quickfix"'],
            \['> git blame', 'Gblame'],
            \['> git stage', 'Gwrite'],
            \['> git checkout', 'exe "Gread " input("checkout: ")'],
            \['> git rm', 'Gremove'],
            \['> git mv', 'exe "Gmove " input("destination: ")'],
            \['> git push', 'Git! push'],
            \['> git pull', 'Git! pull'],
            \['> git prompt', 'exe "Git! " input("git cmd: ")'],
            \['> git cd', 'Gcd'],
            \]

