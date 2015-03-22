let g:ctrlp_by_filename=1

let g:ctrlp_working_path_mode = '0'

set wildignore+=*/target/*
set wildignore+=*/dist/*
set wildignore+=*/plugged/*

function CtrlP_WithDir(dir)
    exe 'cd' a:dir
    :CtrlP a:dir<CR>
endfunction

map ,mm   :CtrlP<CR>
map ,mv   :call CtrlP_WithDir('~/.vim')<CR>
map ,mdw  :call CtrlP_WithDir('~/Downloads')<CR>
map ,mdoc :call CtrlP_WithDir('~/Documents')<CR>
map ,mdr  :call CtrlP_WithDir('~/Dropbox')<CR>
map ,mp   :call CtrlP_WithDir('~/projects')<CR>
map ,mdc  :call CtrlP_WithDir('~/projects/clojure/dunjeon-crawler')<CR>
map ,mma  :call CtrlP_WithDir('~/projects/clojure/clj-mini-apps')<CR>
map ,msms :call CtrlP_WithDir('~/projects/elixir/slugmenu')<CR>
map ,msma :call CtrlP_WithDir('~/AndroidStudioProjects/SlugMenu')<CR>
map ,ml   :call CtrlP_WithDir('~/projects/haskell/loki-lang')<CR>
