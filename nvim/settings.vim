filetype plugin indent on

set mouse=a

" CTRL_SPACE
set hidden

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
set showtabline=2 "always
set tabstop=4 "Tab Literal(\t) == width 4
set visualbell "Dont make noise
set wildmode=list:longest,full

if exists("&undodir")
    set undofile
    set undodir=~/.config/nvim/undo/
    set undolevels=500
    set undoreload=500
endif

let g:terminal_scrollback_buffer_size = 10000
