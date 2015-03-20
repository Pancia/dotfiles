set backspace=indent,eol,start
set nobackup
set history=100
set ruler
set showcmd
set incsearch
set nu
set hlsearch
set noswapfile
set tabstop=4 "Tab (\t) == width 4
set shiftwidth=4 "Indent (Tab) == width 4
set expandtab "Use spaces!
set guifont=Menlo\ Regular:h22
set visualbell
set foldmethod=indent

"Highlight col 121 red, ~ marking it as too long!
highlight ColorColumn ctermbg=magenta
call matchadd('ColorColumn', '\%121v', 100)
