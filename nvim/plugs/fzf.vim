nmap <C-P> :GFiles<CR>

call SEMICOLON_GROUP('f', '+fzf')

call SEMICOLON_CMD('f:', ':Commands', 'FZF Commands')
call SEMICOLON_CMD('fb', ':Buffers', 'FZF Buffers')
call SEMICOLON_CMD('ff', ':Files', 'FZF Files')
call SEMICOLON_CMD('fg', ':GFiles', 'FZF Git files')
call SEMICOLON_CMD('fh', ':Helptags', 'FZF Helptags')
call SEMICOLON_CMD('fk', ':Marks', 'FZF Marks')
call SEMICOLON_CMD('fm', ':Maps', 'FZF Mappings')
call SEMICOLON_CMD('fp', ':GFiles', 'FZF TODO WIP Project')
call SEMICOLON_CMD('fw', ':Windows', 'FZF Windows')

call SEMICOLON_GROUP('fH', 'FZF History')
call SEMICOLON_CMD('fH/', ':History/', 'FZF History Search')
call SEMICOLON_CMD('fH:', ':History:', 'FZF History Commands')
call SEMICOLON_CMD('fHf', ':History', 'FZF History Files')
