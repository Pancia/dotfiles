let g:fzf_layout = { 'window': { 'width': 1.0, 'height': 0.8 } }
let g:fzf_preview_window = ['up:50%', 'ctrl-/']

command! Project :GFiles --other --exclude-standard --cached

function! FilesWithParentNav(dir)
  let start_dir = a:dir != '' ? a:dir : '.'
  let tf = tempname()
  call writefile([fnamemodify(start_dir, ':p')], tf)

  call fzf#run(fzf#wrap({
    \ 'source': 'cd ' . shellescape(start_dir) . ' && fd --type f --hidden --follow --exclude .git . | while read -r file; do echo "$PWD/$file|$file"; done',
    \ 'options': [
    \   '--delimiter', '|',
    \   '--with-nth', '2..',
    \   '--bind',
    \   printf('ctrl-p:reload:base="$(cat %s)"/..; echo "$base" > %s; cd "$base" && fd --type f --hidden --follow --exclude .git . | while read -r file; do echo "$PWD/$file|$file"; done',
    \     shellescape(tf), shellescape(tf))
    \ ],
    \ 'sink': function('s:open_file')
  \ }))
endfunction

function! s:open_file(line)
  let path = split(a:line, '|')[0]
  execute 'edit' fnameescape(path)
endfunction

command! -nargs=? FilesUp call FilesWithParentNav(<q-args>)

function! SmartFuzzyFind()
    let git_dir = system('git rev-parse --is-inside-work-tree 2>/dev/null')
    if v:shell_error == 0
        execute 'Project'
    else
        call FilesWithParentNav('.')
    endif
endfunction

nmap <C-P> :call SmartFuzzyFind()<CR>

call SEMICOLON_CMD(';', ':Commands', 'FZF Commands')
call SEMICOLON_CMD('h', ':Helptags', 'FZF Helptags')

call SEMICOLON_GROUP('f', '+fzf')

call SEMICOLON_CMD('f:', ':Commands', 'FZF Commands')
call SEMICOLON_CMD('fb', ':Buffers', 'FZF Buffers')
call SEMICOLON_CMD('ff', ':Files', 'FZF Files')
call SEMICOLON_CMD('fg', ':Project', 'FZF Git files')
call SEMICOLON_CMD('fh', ':Helptags', 'FZF Helptags')
call SEMICOLON_CMD('fk', ':Marks', 'FZF Marks')
call SEMICOLON_CMD('fm', ':Maps', 'FZF Mappings')
call SEMICOLON_CMD('fp', ':Project', 'FZF Project files')
call SEMICOLON_CMD('fw', ':Windows', 'FZF Windows')

call SEMICOLON_GROUP('fH', 'FZF History')
call SEMICOLON_CMD('fH/', ':History/', 'FZF History Search')
call SEMICOLON_CMD('fH:', ':History:', 'FZF History Commands')
call SEMICOLON_CMD('fHf', ':History', 'FZF History Files')
