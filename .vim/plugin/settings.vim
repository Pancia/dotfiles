set backspace=indent,eol,start
set nobackup
set noswapfile
set history=100
set ruler
set showcmd
set incsearch
set nu
set hlsearch
set tabstop=4 "Tab (\t) == width 4
set shiftwidth=4 "Indent (Tab) == width 4
set expandtab "Use spaces!
set guifont=Menlo\ Regular:h22
set visualbell
set foldmethod=indent
set wildmenu "Visual autocomplete for command menu
set lazyredraw "Silly macros
set cursorline "Highlight line cursor is on

if exists("&undodir")
    set undofile
    set undodir=~/.vim/undo//
    set undolevels=500
    set undoreload=500
endif

"Highlight col 121 red, ~ marking it as too long!
highlight ColorColumn ctermbg=magenta
call matchadd('ColorColumn', '\%121v', 100)
