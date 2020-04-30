nnoremap [unite] <nop>
nmap <space><space> [unite]
nnoremap <silent> [unite]b :Unite buffer<CR>
nnoremap <silent> [unite]<space> :Unite source<CR>
nnoremap <silent> [unite]s :Unite grep:.<CR>
nnoremap <silent> [unite]/ :Unite grep:.<CR>
let g:unite_source_history_yank_enable=1
nnoremap <silent> [unite]y :Unite history/yank<CR>
nnoremap <silent> [unite]p :Unite history/yank<CR>
nnoremap <silent> [unite]h :Unite help<CR>
nnoremap <silent> [unite]u :UndotreeToggle<CR>
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
            \['> vimrc dotfiles', 'e ~/dotfiles/nvim/init.vim | cd ~/dotfiles/nvim'],
            \['> zshrc dotfiles', 'e ~/dotfiles/zsh/init.zsh | cd ~/dotfiles/zsh'],
            \['> delete all buffers', '%bd'],
            \]

let g:unite_source_menu_menus.wiki = {'description' : 'Vimwiki helpers'}
let g:unite_source_menu_menus.wiki.command_candidates = [
            \['Vimwiki Index', 'VimwikiIndex'],
            \['Vimwiki TabIndex', 'VimwikiTabIndex'],
            \['Vimwiki UISelect', 'VimwikiUISelect'],
            \['Vimwiki DiaryIndex', 'VimwikiDiaryIndex'],
            \['Vimwiki MakeDiaryNote', 'VimwikiMakeDiaryNote'],
            \['Vimwiki TabMakeDiaryNote', 'VimwikiTabMakeDiaryNote'],
            \['Vimwiki MakeYesterdayDiaryNote', 'VimwikiMakeYesterdayDiaryNote'],
            \['Vimwiki MakeTomorrowDiaryNote', 'VimwikiMakeTomorrowDiaryNote'],
            \['Vimwiki 2HTML', 'Vimwiki2HTML'],
            \['Vimwiki 2HTMLBrowse', 'Vimwiki2HTMLBrowse'],
            \['Vimwiki DiaryGenerateLinks', 'VimwikiDiaryGenerateLinks'],
            \['Vimwiki FollowLink', 'VimwikiFollowLink'],
            \['Vimwiki SplitLink', 'VimwikiSplitLink'],
            \['Vimwiki VSplitLink', 'VimwikiVSplitLink'],
            \['Vimwiki TabnewLink', 'VimwikiTabnewLink'],
            \['Vimwiki DeleteLink', 'VimwikiDeleteLink'],
            \['Vimwiki RenameLink', 'VimwikiRenameLink'],
            \]

let g:unite_source_menu_menus.plug = {}
let g:unite_source_menu_menus.plug.command_candidates = [
            \['PlugInstall', 'source % | PlugInstall'],
            \['PlugClean', 'source % | PlugClean'],
            \]

let g:unite_source_menu_menus.fulcro = {'description' : 'Fulcro Project Commands'}
let g:unite_source_menu_menus.fulcro.command_candidates = [
            \['restart', "ConjureEval (require '[development :as dev])(dev/restart)"],
            \]
