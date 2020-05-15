let g:LanguageClient_serverCommands = {
    \ 'clojure': ['clojure-lsp'],
    \ }

set completefunc=LanguageClient#complete

nnoremap <silent> K :call LanguageClient#textDocument_hover()<CR>
nnoremap <silent> gd :call LanguageClient#textDocument_definition()<CR>

let g:LanguageClient_settingsPath=".lsp/settings.json"
