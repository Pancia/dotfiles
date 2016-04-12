let g:paredit_shortmaps=0
let g:airline_detect_whitespace=0

"goto definition
map gd [<c-d>
"show source
map gs [d

let g:clojure_maxlines=300
let g:clojure_align_multiline_strings=0
let g:clojure_syntax_keywords = {
    \ 'clojureMacro': ['defui', 'facts', 'fact', 'specification', 'behavior', 'provided', 'assertions', 'component', 'render', 'query', 'ident']
    \ }

let g:clojure_fuzzy_indent = 1
let g:clojure_fuzzy_indent_patterns = ['^def.*', '^with.*', 'specification', 'behavior', 'assertions', 'component']
let g:clojure_fuzzy_indent_blacklist = []
let g:clojure_special_indent_words = 'defui'
