let g:which_key_map = {}

for plug_conf in split(globpath(expand("<sfile>:p:h"), 'plugs/*.vim'), '\n')
    execute 'source ' . plug_conf
endfor

for ftp in split(globpath('~/dotfiles/nvim/ftplugin', '*.vim'), '\n')
    let base_ftp = fnamemodify(ftp,":t")
    let dest_ftp = expand('~/.config/nvim/ftplugin/'.base_ftp)
    if !filereadable(dest_ftp)
        call system('echo "source ~/dotfiles/nvim/ftplugin/'.base_ftp.'" > '.dest_ftp)
    endif
endfor
