call SEMICOLON_GROUP('t', '+theme')
call SEMICOLON_CMD('tt', ':VCoolor', 'open color picker')
call SEMICOLON_CMD('ta', ":echo synIDattr(synID(line('.'), col('.'), 0), 'name')", 'show syntax attribute')
call SEMICOLON_CMD('td', ":echo ('hi<' . synIDattr(synID(line('.'),col('.'),1),'name') . '> trans<' . synIDattr(synID(line('.'),col(' '),0),'name') . '> lo<' . synIDattr(synIDtrans(synID(line('.'),col('.'),1)),'name') . '>')", 'debug syntax')
call SEMICOLON_CMD('ts', ":echo map(synstack(line('.'), col('.')), 'synIDattr(v:val, \"name\")')", 'show syntax stack')
call SEMICOLON_CMD('tl', ":exec 'syn list '.synIDattr(synID(line('.'), col('.'), 0), 'name')", 'list syntax rules')

