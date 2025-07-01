function! ShowSyntaxAttr()
    echo synIDattr(synID(line('.'), col('.'), 0), 'name')
endfunction

function! DebugSyntax()
    echo ('hi<' . synIDattr(synID(line('.'),col('.'),1),'name') . '> trans<' . synIDattr(synID(line('.'),col('.'),0),'name') . '> lo<' . synIDattr(synIDtrans(synID(line('.'),col('.'),1)),'name') . '>')
endfunction

function! ShowSyntaxStack()
    echo map(synstack(line('.'), col('.')), 'synIDattr(v:val, "name")')
endfunction

function! ListSyntaxRules()
    exec 'syn list '.synIDattr(synID(line('.'), col('.'), 0), 'name')
endfunction

call SEMICOLON_GROUP('t', '+THEME')
call SEMICOLON_CMD('tt', ':VCoolor', 'OPEN COLOR PICKER')
call SEMICOLON_CMD('ta', ":call ShowSyntaxAttr()", 'SHOW SYNTAX ATTRIBUTE')
call SEMICOLON_CMD('td', ":call DebugSyntax()", 'DEBUG SYNTAX')
call SEMICOLON_CMD('ts', ":call ShowSyntaxStack()", 'SHOW SYNTAX STACK')
call SEMICOLON_CMD('tl', ":call ListSyntaxRules()", 'LIST SYNTAX RULES')
