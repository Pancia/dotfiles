let g:ctrlp_by_filename=1

let g:ctrlp_working_path_mode = '0'

set wildignore+=*/target/*
set wildignore+=*/dist/*
set wildignore+=*/plugged/*

function CtrlP_WithDir(dir)
    exe 'cd' a:dir
    :CtrlP a:dir<CR>
endfunction

map ,mm :CtrlP<CR>
map ,mv :call CtrlP_WithDir('~/.vim')<CR>
map ,ml :call CtrlP_WithDir('~/UCSC/loki-lang')<CR>
