set shiftwidth=2
set tabstop=2

call onedark#set_highlight("clojureKeyword", {"fg": {"gui": "#EE2DB2", "cterm": "NONE"}})

let g:airline_detect_whitespace=0

let g:clojure_maxlines=300
let g:clojure_align_multiline_strings=1
let g:clojure_syntax_keywords = {
      \ 'clojureMacro': [
      \   'defsc', '>defn', 'defmutation',
      \   'specification', 'behavior', 'provided', 'assertions', 'component',
      \   'provided', 'when-mocking', 'provided!', 'when-mocking!',
      \   'defrule', 'defstate',
      \   ]
      \ }

let g:clojure_fuzzy_indent = 1
let g:clojure_fuzzy_indent_patterns = '.*'
let g:clojure_fuzzy_indent_blacklist = []

nnoremap <buffer><silent> ,fr :ConjureEval (require 'user)(in-ns 'user)(require 'development)(in-ns 'development)(restart)<CR>

setlocal completefunc=LanguageClient#complete

nnoremap <buffer><silent> <F5> :call LanguageClient_contextMenu()<CR>
nnoremap <buffer><silent> K    :call LanguageClient#textDocument_hover()<CR>
nnoremap <buffer><silent> gd   :call LanguageClient#textDocument_definition()<CR>

nnoremap <buffer><expr> <esc> bufname('') =~ 'conjure-log-\d\+.cljc' ? ':normal ,lq<CR>' : '<esc>'
