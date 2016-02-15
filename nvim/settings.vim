filetype plugin indent on

" CTRL_SPACE
set hidden
set showtabline=0

set cursorline "Highlight line cursor is on
set expandtab "Use spaces, not tabs!
set foldmethod=indent
set lazyredraw "Silly macros
set nobackup
set nofileignorecase "Dont ignore case when cmd/ex mode
set noswapfile
set number
set ruler
set shiftwidth=4 "Indent Key(Tab) == width 4
set showcmd
set tabstop=4 "Tab Literal(\t) == width 4
set visualbell "Dont make noise
set wildmode=list:longest,full

if exists("&undodir")
    set undofile
    set undodir=~/.config/nvim/undo/
    set undolevels=500
    set undoreload=500
endif
