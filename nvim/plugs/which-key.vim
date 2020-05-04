let g:mapleader = "\<Space>\<Space>"
let g:maplocalleader = ","

nnoremap <silent> <leader> :<c-u>WhichKey '<Space><Space>'<CR>
nnoremap <silent> ,        :<c-u>WhichKey              ','<CR>

set timeoutlen=500
let g:which_key_use_floating_win = 0

call which_key#register('  ', "g:which_key_map")

let g:which_key_map['<NL>'] = 'which_key_ignore'
let g:which_key_map['%'] = 'which_key_ignore'

let g:which_key_map.g = {}
