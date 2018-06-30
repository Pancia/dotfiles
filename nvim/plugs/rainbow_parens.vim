let g:rbpt_max = 32
let g:rbpt_colorpairs = [
    \ ['brown',       'RoyalBlue3'],
    \ ['Darkblue',    'SeaGreen3'],
    \ ['darkgray',    'DarkOrchid3'],
    \ ['darkgreen',   'firebrick3'],
    \ ['darkcyan',    'RoyalBlue3'],
    \ ['darkred',     'SeaGreen3'],
    \ ['darkmagenta', 'DarkOrchid3'],
    \ ['brown',       'firebrick3'],
    \ ['gray',        'RoyalBlue3'],
    \ ['darkmagenta', 'DarkOrchid3'],
    \ ['Darkblue',    'firebrick3'],
    \ ['darkgreen',   'RoyalBlue3'],
    \ ['darkcyan',    'SeaGreen3'],
    \ ['darkred',     'DarkOrchid3'],
    \ ['red',         'firebrick3'],
    \ ]

augroup RainbowParens
    au!
    let rp_blacklist = ['javascript']
    au VimEnter * if index(rp_blacklist, &ft) < 0 | RainbowParenthesesToggle
    au Syntax * if index(rp_blacklist, &ft) < 0 | RainbowParenthesesLoadRound
    au Syntax * if index(rp_blacklist, &ft) < 0 | RainbowParenthesesLoadSquare
    au Syntax * if index(rp_blacklist, &ft) < 0 | RainbowParenthesesLoadBraces
augroup END

