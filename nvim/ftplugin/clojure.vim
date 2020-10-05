set shiftwidth=2
set tabstop=2

highlight link clojureKeyword Constant

let g:airline_detect_whitespace=0

let g:clojure_maxlines=300
let g:clojure_align_multiline_strings=1
let g:clojure_syntax_keywords = {
      \ 'clojureMacro': [
      \   'defsc', '>defn', 'defmutation',
      \   'specification', 'behavior', 'provided', 'assertions', 'component',
      \   'provided', 'when-mocking', 'provided!', 'when-mocking!',
      \   ]
      \ }

let g:clojure_fuzzy_indent = 1
let g:clojure_fuzzy_indent_patterns = '.*'
let g:clojure_fuzzy_indent_blacklist = []

nnoremap <buffer><silent> ,fr :ConjureEval (require 'user)(in-ns 'user)(require 'development)(in-ns 'development)(restart)<CR>

nnoremap <buffer><expr> <esc> bufname('') =~ 'conjure-log-\d\+.cljc' ? ':normal ,lq<CR>' : '<esc>'

setlocal completefunc=LanguageClient#complete

nnoremap <buffer><silent> K    :call LanguageClient#textDocument_hover()<CR>
nnoremap <buffer><silent> gd   :call LanguageClient#textDocument_definition()<CR>

function! s:Expand(exp) abort
    let l:result = expand(a:exp)
    return l:result ==# '' ? '' : "file://" . l:result
endfunction

function! LSP_exe_here(cmd, ...) abort
  call LanguageClient#workspace_executeCommand(a:cmd,
        \ [s:Expand('%:p'), line('.') - 1, col('.') - 1] + a:000)
endfunction

function! LSP_restart()
    LanguageClientStop
    LanguageClientStart
endfunction

call WhichKey_GROUP('s', '+lsp')
call WhichKey_CMD('ss', 'restart', 'LSP_restart()')

call WhichKey_GROUP('sr', '+refactorings')

call WhichKey_GROUP('srt', '+threading')
call WhichKey_CMD('srtf', 'thread-first', 'LSP_exe_here("thread-first")')
call WhichKey_CMD('srtt', 'thread-last', 'LSP_exe_here("thread-last")')
call WhichKey_CMD('srtF', 'thread-first-all', 'LSP_exe_here("thread-first-all")')
call WhichKey_CMD('srtT', 'thread-last-all', 'LSP_exe_here("thread-last-all")')
call WhichKey_CMD('srtu', 'unwind-thread', 'LSP_exe_here("unwind-thread")')
call WhichKey_CMD('srtU', 'unwind-all', 'LSP_exe_here("unwind-all")')

call WhichKey_GROUP('srr', '+requires')
call WhichKey_CMD('srra', 'add-missing-libspec', 'LSP_exe_here("add-missing-libspec")')

call WhichKey_GROUP('srl', '+let')
call WhichKey_CMD('srle', 'expand-let', 'LSP_exe_here("expand-let")')
call WhichKey_CMD('srlm', 'move-to-let', 'LSP_exe_here("move-to-let", input("Binding name: "))')
call WhichKey_CMD('srli', 'introduce-let', 'LSP_exe_here("introduce-let", input("Binding name: "))')
call WhichKey_CMD('su', 'find usages', 'LanguageClient#textDocument_references()')

nnoremap <buffer><silent> ,, :call guardrails_pro#run_check()<CR>
