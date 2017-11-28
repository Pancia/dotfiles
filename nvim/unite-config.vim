nnoremap [unite] <nop>
nmap <space><space> [unite]
nnoremap <silent> [unite]f :Unite file_rec/neovim<CR>
nnoremap <silent> [unite]p :CtrlP<CR>
nnoremap <silent> [unite]b :Unite buffer<CR>
nnoremap <silent> [unite]t :Unite file/async:t<CR>
nnoremap <silent> [unite]<space> :Unite source<CR>
nnoremap <silent> [unite]s :Unite grep:.<CR>
nnoremap <silent> [unite]r :Unite rust/doc<CR>
let g:unite_source_history_yank_enable=1
nnoremap <silent> [unite]y :Unite history/yank<CR>
nnoremap <silent> [unite]h :Unite help<CR>
nnoremap <silent> [unite]u :GundoToggle<CR>
nnoremap <silent> [unite]: :Unite command mapping<CR>
nnoremap <silent> <c-space> :Unite menu<CR>
nnoremap <silent> <NUL>     :Unite menu<CR>

autocmd FileType unite call s:unite_settings()
function! s:unite_settings()
    imap <buffer> <C-j> <Plug>(unite_select_next_line)
    imap <buffer> <C-k> <Plug>(unite_select_previous_line)
    nmap <buffer> <ESC> <Plug>(unite_all_exit)
endfunction

call unite#custom#profile('default', 'context', {
            \   'start_insert': 1,
            \   'winheight': 15,
            \   'direction': 'botright',
            \ })

if executable('ag')
    let g:unite_source_grep_command = 'ag'
    let g:unite_source_grep_default_opts = '--vimgrep --nocolor'
    let g:unite_source_grep_recursive_opt = ''
endif

call unite#filters#matcher_default#use(['matcher_fuzzy'])

let g:unite_source_menu_menus = get(g:, 'unite_source_menu_menus', {})
let g:unite_source_menu_menus.git = {'description' : 'fugitive commands'}
let g:unite_source_menu_menus.git.command_candidates = [
            \['> git status', 'Gstatus'],
            \['> git diff', 'Gdiff'],
            \['> git commit', 'Gcommit'],
            \['> git log', 'exe "silent Glog | Unite quickfix"'],
            \['> git blame', 'Gblame'],
            \['> git stage', 'Gwrite'],
            \['> git checkout', 'exe "Gread " input("checkout: ")'],
            \['> git rm', 'Gremove'],
            \['> git mv', 'exe "Gmove " input("destination: ")'],
            \['> git push', 'Git! push'],
            \['> git pull', 'Git! pull'],
            \['> git prompt', 'exe "Git! " input("git cmd: ")'],
            \['> git cd', 'Gcd'],
            \]

let g:unite_source_menu_menus._helpers = {'description' : 'my custom helpers'}
let g:unite_source_menu_menus._helpers.command_candidates = [
            \['> source current file', 'source %'],
            \['> zshrc dotfiles', 'e ~/dotfiles/zshrc | cd ~/dotfiles/zsh'],
            \['> vimrc dotfiles', 'e ~/dotfiles/nvim/init.vim | cd ~/dotfiles/nvim'],
            \['> lein profiles', 'e ~/.lein/profiles.clj | cd ~/.lein'],
            \['> delete all buffers', '%bd'],
            \['> tidy', 'g/^\s\+[\)\]\}]/normal kJ'],
            \]

let g:unite_source_menu_menus.plug = {}
let g:unite_source_menu_menus.plug.command_candidates = [
            \['PlugInstall', 'source % | PlugInstall'],
            \]

let g:unite_source_menu_menus.java = {'description' : 'JavaComplete'}
let g:unite_source_menu_menus.java.command_candidates = [
            \[],
            \]

"JCimportsSort
"JCimportsRemoveUnused
"JCimportsAddMissing
"JCimportAddSmart
"JCimportAdd

"TODO
"To enable smart (trying to guess import option) inserting class imports with F4, add:
"
"nmap <F4> <Plug>(JavaComplete-Imports-AddSmart)
"
"imap <F4> <Plug>(JavaComplete-Imports-AddSmart)
"
"To enable usual (will ask for import option) inserting class imports with F5, add:
"
"nmap <F5> <Plug>(JavaComplete-Imports-Add)
"
"imap <F5> <Plug>(JavaComplete-Imports-Add)
"
"To add all missing imports with F6:
"
"nmap <F6> <Plug>(JavaComplete-Imports-AddMissing)
"
"imap <F6> <Plug>(JavaComplete-Imports-AddMissing)
"
"To remove all unused imports with F7:
"
"nmap <F7> <Plug>(JavaComplete-Imports-RemoveUnused)
"
"imap <F7> <Plug>(JavaComplete-Imports-RemoveUnused)
"
"Default mappings:

" nmap <leader>jI <Plug>(JavaComplete-Imports-AddMissing)
" nmap <leader>jR <Plug>(JavaComplete-Imports-RemoveUnused)
" nmap <leader>ji <Plug>(JavaComplete-Imports-AddSmart)
" nmap <leader>jii <Plug>(JavaComplete-Imports-Add)

" imap <C-j>I <Plug>(JavaComplete-Imports-AddMissing)
" imap <C-j>R <Plug>(JavaComplete-Imports-RemoveUnused)
" imap <C-j>i <Plug>(JavaComplete-Imports-AddSmart)
" imap <C-j>ii <Plug>(JavaComplete-Imports-Add)

" nmap <leader>jM <Plug>(JavaComplete-Generate-AbstractMethods)

" imap <C-j>jM <Plug>(JavaComplete-Generate-AbstractMethods)

" nmap <leader>jA <Plug>(JavaComplete-Generate-Accessors)
" nmap <leader>js <Plug>(JavaComplete-Generate-AccessorSetter)
" nmap <leader>jg <Plug>(JavaComplete-Generate-AccessorGetter)
" nmap <leader>ja <Plug>(JavaComplete-Generate-AccessorSetterGetter)
" nmap <leader>jts <Plug>(JavaComplete-Generate-ToString)
" nmap <leader>jeq <Plug>(JavaComplete-Generate-EqualsAndHashCode)
" nmap <leader>jc <Plug>(JavaComplete-Generate-Constructor)
" nmap <leader>jcc <Plug>(JavaComplete-Generate-DefaultConstructor)

" imap <C-j>s <Plug>(JavaComplete-Generate-AccessorSetter)
" imap <C-j>g <Plug>(JavaComplete-Generate-AccessorGetter)
" imap <C-j>a <Plug>(JavaComplete-Generate-AccessorSetterGetter)

" vmap <leader>js <Plug>(JavaComplete-Generate-AccessorSetter)
" vmap <leader>jg <Plug>(JavaComplete-Generate-AccessorGetter)
" vmap <leader>ja <Plug>(JavaComplete-Generate-AccessorSetterGetter)

" nmap <silent> <buffer> <leader>jn <Plug>(JavaComplete-Generate-NewClass)
" nmap <silent> <buffer> <leader>jN <Plug>(JavaComplete-Generate-ClassInFile)

