nnoremap [unite] <nop>
nmap <space><space> [unite]
nnoremap <silent> [unite]f :Unite file_rec/neovim<CR>
nnoremap <silent> [unite]p :CtrlP<CR>
nnoremap <silent> [unite]b :Unite buffer<CR>
nnoremap <silent> [unite]t :Unite file/async:t<CR>
nnoremap <silent> [unite]<space> :Unite source<CR>
nnoremap <silent> [unite]s :Unite grep:.<CR>
let g:unite_source_history_yank_enable=1
nnoremap <silent> [unite]y :Unite history/yank<CR>
nnoremap <silent> [unite]h :Unite help<CR>
nnoremap <silent> [unite]u :GundoToggle<CR>
nnoremap <silent> [unite]: :Unite command mapping<CR>
nnoremap <silent> <c-space> :Unite menu<CR>

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

let g:unite_source_menu_menus.helpers = {'description' : 'my custom helpers'}
let g:unite_source_menu_menus.helpers.command_candidates = [
            \['> source current file', 'source %'],
            \['> zshrc dotfiles', 'e ~/dotfiles/zshrc | cd ~/dotfiles/zsh'],
            \['> vimrc dotfiles', 'e ~/dotfiles/nvim/init.vim | cd ~/dotfiles/nvim'],
            \['> lein profiles', 'e ~/.lein/profiles.clj | cd ~/.lein'],
            \['> delete all buffers', '%bd'],
            \['> tidy', 'g/^\s\+[\)\]\}]/normal kJ'],
            \]
