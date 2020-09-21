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
      \   'defrule', 'defstate',
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

let g:semicolon_which_key_map['s'] = {'name': '+lsp'}
let g:semicolon_which_key_map['s']['r'] = {'name': '+refactorings'}
let g:semicolon_which_key_map['s']['r']['t'] = {'name': '+threading'}
let g:semicolon_which_key_map['s']['r']['t']['h'] = [':execute "call LSP_exe_here(\"thread-first\")"', 'thread-first']
let g:semicolon_which_key_map['s']['r']['t']['t'] = [':execute "call LSP_exe_here(\"thread-last\")"', 'thread-last']
let g:semicolon_which_key_map['s']['r']['t']['f'] = [':execute "call LSP_exe_here(\"thread-first-all\")"', 'thread-first-all']
let g:semicolon_which_key_map['s']['r']['t']['l'] = [':execute "call LSP_exe_here(\"thread-last-all\")"', 'thread-last-all']
let g:semicolon_which_key_map['s']['r']['r'] = {'name': '+requires'}
let g:semicolon_which_key_map['s']['r']['r']['a'] = [':execute "call LSP_exe_here(\"add-missing-libspec\")"', 'add-missing-libspec']
let g:semicolon_which_key_map['s']['r']['l'] = {'name': '+let'}
let g:semicolon_which_key_map['s']['r']['l']['e'] = [':execute "call LSP_exe_here(\"expand-let\")"', 'expand-let']
let g:semicolon_which_key_map['s']['r']['l']['m'] = [':execute "call LSP_exe_here(\"move-to-let\", input(\"Binding name: \"))"', 'move-to-let']
let g:semicolon_which_key_map['s']['r']['l']['i'] = [':execute "call LSP_exe_here(\"introduce-let\", input(\"Binding name: \"))"', 'introduce-let']

let g:semicolon_which_key_map['s']['u'] = [':execute "call LanguageClient#textDocument_references()"', 'find usages']
