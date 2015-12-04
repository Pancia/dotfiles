" PLUGINS "{{{
call plug#begin('~/.vim/plugged')
" Essentials {{{
Plug 'vim-scripts/vim-auto-save'
Plug 'bling/vim-airline'
Plug 'christoomey/vim-tmux-navigator'
Plug 'kien/ctrlp.vim'
Plug 'sjl/gundo.vim'
Plug 'tpope/vim-repeat'
Plug 'scrooloose/syntastic'
Plug 'godlygeek/tabular'
Plug 'kien/rainbow_parentheses.vim'
Plug 'kshenoy/vim-signature'
Plug 'majutsushi/tagbar'
Plug 'ntpeters/vim-better-whitespace'
Plug 'takac/vim-spotifysearch'
Plug 'tpope/vim-dispatch'
Plug 'tpope/vim-projectionist'
Plug 'tpope/vim-speeddating'
Plug 'tpope/vim-surround'
Plug 'vim-scripts/Conque-Shell'
Plug 'vim-scripts/bufkill.vim'
" }}} Essentials
" {{{ Git
Plug 'tpope/vim-fugitive'
Plug 'rhysd/conflict-marker.vim'
" }}}
" Movement {{{
Plug 'Lokaltog/vim-easymotion'
Plug 'deris/vim-shot-f'
Plug 'Shougo/vimproc.vim',     { 'do' : 'make -f make_mac.mak' }
Plug 'shinokada/dragvisuals.vim'
" }}} Movement
" AutoComplete {{{
Plug 'Valloric/YouCompleteMe', { 'do' : 'git submodule update --init --recursive; ./install.sh --clang-completer' }
Plug 'honza/vim-snippets'
Plug 'sirver/ultisnips'
" }}} AutoComplete
" Clojure {{{
Plug 'guns/vim-clojure-static'
Plug 'guns/vim-clojure-highlight'
Plug 'guns/vim-sexp'
Plug 'tpope/vim-sexp-mappings-for-regular-people'
Plug 'tpope/vim-fireplace'
Plug 'clojure-emacs/cider-nrepl'
" }}} Clojure
" Scala {{{
Plug 'derekwyatt/vim-scala'
" }}}
" Haskell {{{
Plug 'dag/vim2hs',          { 'for' : 'haskell' }
Plug 'eagletmt/ghcmod-vim', { 'for' : 'haskell' }
Plug 'eagletmt/neco-ghc',   { 'for' : 'haskell' }
" }}} Haskell
" Elixir {{{
Plug 'elixir-lang/vim-elixir', { 'for' : 'elixir' }
" }}} Elixir
" Prolog {{{
Plug 'adimit/prolog.vim', { 'for' : 'prolog' }
" }}} Prolog
" JavaScript {{{
"Plug 'jelera/vim-javascript-syntax'
Plug 'digitaltoad/vim-jade'
Plug 'wavded/vim-stylus'
" }}} JavaScript
" Node.js {{{
Plug 'sidorares/node-vim-debugger'
Plug 'moll/vim-node'
Plug 'marijnh/tern_for_vim'
" }}} Node.js
" {{{ Rust
Plug 'rust-lang/rust.vim'
Plug 'ebfe/vim-racer'
" }}}
call plug#end()
" }}} PLUGINS

" PLUGIN CONFIG {{{
" RUST {{{
set hidden
let g:racer_cmd = "~/Developer/racer/target/release/racer"
let $RUST_SRC_PATH="/Users/pancia/Developer/rustc-1.2.0/src"
" }}}

" AUTO_SAVE {{{
let g:auto_save=1
let g:auto_save_in_insert_mode=0
" }}} AUTO_SAVE

" CTRLP {{{
let g:ctrlp_working_path_mode = 'ra'
let g:ctrlp_user_command = ['.git/', 'git --git-dir=%s/.git ls-files -oc --exclude-standard']
set wildignore+=*/target/*,*/dist/*,*/build/*,*/build/*,*.o
set wildignore+=*/.vim/autoload/*,*/.vim/bundle/*,*/.vim/plugged/*
set wildignore+=*/node_modules/*,*/resources/*/out/*,*/resources/public/js/*
set wildignore+=*/resources/public/cards/*
" }}} CTRLP

" EASYMOTION {{{
"map <Space>  <Plug>(easymotion-prefix)
map <Space>j <Plug>(easymotion-j)
map <Space>k <Plug>(easymotion-k)
map <Space>s <Plug>(easymotion-s)
map //       <Plug>(easymotion-sn)
" }}} EASYMOTION

" DRAGVISUALS {{{
vmap <expr> <LEFT>  DVB_Drag('left')
vmap <expr> <RIGHT> DVB_Drag('right')
vmap <expr> <DOWN>  DVB_Drag('down')
vmap <expr> <UP>    DVB_Drag('up')
vmap <expr> D       DVB_Duplicate()
" }}} DRAGVISUALS

" AIRLINE {{{
let g:airline#extensions#tabline#enabled=1
set laststatus=2 "Always show status line
" }}} AIRLINE

" SYNTASTIC {{{
set statusline+=%#warningmsg#
set statusline+=%{SyntasticStatuslineFlag()}
set statusline+=%*
let g:syntastic_always_populate_loc_list = 1
let g:syntastic_auto_loc_list = 1
let g:syntastic_check_on_open = 0
let g:syntastic_check_on_wq = 0
let g:syntastic_aggregate_errors = 1
let g:syntastic_mode_map = {
            \ "mode": "active",
            \ }
let g:syntastic_javascript_checkers = ['eslint']
let g:syntastic_json_checkers = ['jsonlint']
let g:syntastic_elixir_checkers = ['elixir']
let g:syntastic_enable_elixir_checker = 1
let g:syntastic_cpp_compiler = 'clang'
let g:syntastic_cpp_compiler_options = '-g -O0 -Wall -Wextra -Wpedantic -std=c++11'
augroup syntastic_plus_autosave
    au CursorHold,InsertLeave * nested update
augroup END
" }}} SYNTASTIC

" ULTISNIPS {{{
let g:UltiSnipsExpandTrigger="<ctrl><cr>"
" }}} ULTISNIPS

" YOUCOMPLETEME {{{
let g:ycm_semantic_triggers = {'haskell' : ['.'], 'javascript' : ['.']}
" Helps with cpp and synastic
" - https://github.com/Valloric/YouCompleteMe#the-gycm_show_diagnostics_ui-option
let g:ycm_show_diagnostics_ui = 0
" Enables & configures semantic completion for c,c++...
let g:ycm_global_ycm_extra_conf = "~/.vim/.ycm_extra_conf.py"
let g:ycm_autoclose_preview_window_after_insertion = 1
" TODO: NOT WORKING, Disable arrow keys
let g:ycm_key_list_select_completion = ['<TAB>']
let g:ycm_key_list_previous_completion = ['<S-TAB>']
" }}} YOUCOMPLETEME

" TAGBAR {{{
let g:tagbar_left = 1
" }}} TAGBAR

" MISC {{{
let g:strip_whitespace_on_save = 1
" }}} MISC
" }}} PLUGIN CONFIG

" MAPPINGS {{{
" Disable arrows
nmap <up> <nop>
nmap <down> <nop>
nmap <left> <nop>
nmap <right> <nop>
nmap <Space> <nop>
nmap <CR> <nop>
" Leader mappings
let mapleader = "<Space>"
map s \
map <Space><Space> \
" Swap j,k with gj,gk
noremap j gj
noremap k gk
noremap gj j
noremap gk k
" map Q to gQ, which is a more useful `q:`
noremap Q gQ
" U redoes
nnoremap U <c-r>
" ctrl-e removes last search highlighting
nnoremap <c-e> /reset\.search<CR>:nohlsearch<CR>
" Use BS to navigate cursor history
nmap <BS>   <c-o>zz
nmap <S-BS> <c-i>zz
" Center screen when searching
nnoremap n nzz
nnoremap N Nzz
nnoremap * *zz
nnoremap # #zz
nnoremap g* g*zz
nnoremap g# g#zz
" alt: {j :bp, k :bn, h :tabp, l :tabn}
map ˚ :bnext<CR>
map ∆ :bprevious<CR>
map ˙ :tabp<CR>
map ¬ :tabn<CR>
" Enter.+ mappings
map <CR>pi   :PlugInstall<CR>
map <CR>pc   :PlugInPlugClean<CR>
map <CR>bsh  :e ~/cfg/bashrc<CR>
map <CR>vim  :e ~/cfg/vimrc<CR>:cd ~/cfg/vim<CR>
map <CR>so   :so %<CR>
map <CR>u    :GundoToggle<CR>
map <CR>tb   :TagbarToggle<CR>
map <CR>bda  :bd *<CR>
map <CR>tidy :g/^\s\+[\)\]\}]/normal kJ<CR>
command! Tidy g/^\s\+[\)\]\}]/normal kJ<CR>

"}}} MAPPINGS

"NAVIS STUFF {{{
command! UnFocus %s/:focused //g
command! Focus %s/\(facts\?\)/\1 :focused/g
"}}}

" SETTINGS {{{
filetype plugin indent on
set backspace=indent,eol,start
set nobackup
set noswapfile
set history=100 "Number of mdl lines
set ruler
set showcmd
set incsearch
set number
set hlsearch
set tabstop=4 "Tab Literal(\t) == width 4
set shiftwidth=4 "Indent Key(Tab) == width 4
set expandtab "Use spaces, not tabs!
set smarttab "Indent & delete by shiftwidth
set guifont=Menlo\ Regular:h17
let tv=$TV
if tv == "0"
    set lines=44 columns=86
endif
set visualbell "Dont make noise
set foldmethod=indent
set wildmenu "Visual autocomplete for command menu
set wildmode=list:longest,full
set lazyredraw "Silly macros
set cursorline "Highlight line cursor is on
set nofileignorecase "Dont ignore case when cmd/ex mode
if exists("&undodir")
    set undofile
    "store undo files in .vim/undo & make the path unique
    set undodir=~/.vim/undo//
    set undolevels=500
    set undoreload=500
endif
" }}} SETTINGS

" THEME {{{
colorscheme onedark
"silent! colorscheme macvim
"hi folded guibg=#707070
" }}} THEME

" AUTOGROUPS {{{
function! SetCursorToLastKnownPosition()
    if &filetype !~ 'git\|commit\c'
        if line("'\"") > 1 && line("'\"") <= line("$")
            exe "normal! g`\""
            normal! zz
            normal! zR
        endif
    endif
endfunction
augroup Essentials
    au!
    au FileType text setlocal textwidth=80
    au BufReadPost * call SetCursorToLastKnownPosition()
    au FileType vim setlocal foldmethod=marker
    autocmd BufEnter * silent! lcd %:p:h " Eqv to `set autochdir`
augroup END
augroup RainbowParens
    au!
    let rp_blacklist = ['javascript']
    au VimEnter * if index(rp_blacklist, &ft) < 0 | RainbowParenthesesToggle
    au Syntax * if index(rp_blacklist, &ft) < 0 | RainbowParenthesesLoadRound
    au Syntax * if index(rp_blacklist, &ft) < 0 | RainbowParenthesesLoadSquare
    au Syntax * if index(rp_blacklist, &ft) < 0 | RainbowParenthesesLoadBraces
augroup END
augroup Assorted
    au BufNewFile,BufRead *.loki set filetype=clojure
    au BufNewFile,BufRead .eslintrc set filetype=json
augroup END
" }}} AUTOGROUPS
