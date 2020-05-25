let g:unite_source_menu_menus.plug = {'description' : 'vim-plug'}
let g:unite_source_menu_menus.plug.command_candidates = [
            \['PlugInstall', 'source % | PlugInstall'],
            \['PlugClean', 'source % | PlugClean!'],
            \['PlugUpdate', 'source % | PlugUpdate'],
            \]
