let g:semicolon_which_key_map.t = {
            \ 'name' : '+theme',
            \ 't' : [':VCoolor', 'open color picker'],
            \ 'a' : [":echo synIDattr(synID(line('.'), col('.'), 0), 'name')", 'show syntax attribute'],
            \ 'd' : [":echo ('hi<' . synIDattr(synID(line('.'),col('.'),1),'name') . '> trans<' . synIDattr(synID(line('.'),col(' '),0),'name') . '> lo<' . synIDattr(synIDtrans(synID(line('.'),col('.'),1)),'name') . '>')", 'debug syntax'],
            \ 's' : [":echo map(synstack(line('.'), col('.')), 'synIDattr(v:val, \"name\")')", 'show syntax stack'],
            \ 'l' : [":exec 'syn list '.synIDattr(synID(line('.'), col('.'), 0), 'name')", 'list syntax rules'],
            \ }
