let g:paredit_shortmaps=0
let g:airline_detect_whitespace=0

"goto definition
map gd [<c-d>
"show source
map gs [d

let g:clojure_maxlines=300
let g:clojure_align_multiline_strings=0
let g:clojure_syntax_keywords = {
    \ 'clojureMacro': ['defui', 'defhtml', 'defroutes', 'GET', 'POST', 'facts', 'fact', 'specification', 'behavior', 'provided', 'assertions', 'component']
    \ }

let g:clojure_fuzzy_indent = 1
let g:clojure_fuzzy_indent_patterns = ['^def', '^let', 'specification', 'behavior', 'provided', 'assertions', 'component']

let g:clojure_fuzzy_indent_blacklist = ['defui']

setlocal tabstop=4 "Tab Literal(\t)
setlocal shiftwidth=4 "Indent Key(Tab)
