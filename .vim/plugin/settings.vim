set backspace=indent,eol,start
set nobackup
set noswapfile
set history=100 "Number of mdl lines
set ruler
set showcmd
set incsearch
set nu
set hlsearch
set tabstop=4 "Tab Literal(\t) == width 4
set shiftwidth=4 "Indent Key(Tab) == width 4
set expandtab "Use spaces!
set guifont=Menlo\ Regular:h22
set visualbell "Dont make noise
set foldmethod=indent
set wildmenu "Visual autocomplete for command menu
set lazyredraw "Silly macros
set cursorline "Highlight line cursor is on

if exists("&undodir")
    set undofile
    "store undo files in .vim/undo & make the path unique
    set undodir=~/.vim/undo//
    set undolevels=500
    set undoreload=500
endif

let g:strip_whitespace_on_save = 1
