let g:android_sdk_path = '/Users/Anthony/Library/Android/sdk'

augroup JAVA
    au!
    au FileType java setlocal omnifunc=javacomplete#Complete
    function! FindConfig(what)
        silent! lcd %:p:h
        return findfile(a:what, expand('%:p:h') . ';')
    endfunction
    au FileType java let g:syntastic_java_javac_config_file = FindConfig('.syntastic_javac_config')
augroup END

augroup KOTLIN
    au!
    au FileType kotlin setlocal omnifunc=javacomplete#Complete
augroup END
