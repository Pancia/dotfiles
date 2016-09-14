let g:paredit_shortmaps=0
let g:airline_detect_whitespace=0

"goto definition
map gd [<c-d>
"show source
map gs [d

let g:clojure_maxlines=300
let g:clojure_align_multiline_strings=1
let g:clojure_syntax_keywords = {
    \ 'clojureMacro': ['defui', 'facts', 'fact', 'specification', 'behavior', 'provided', 'assertions', 'component', 'provided', 'when-mocking', 'render', 'query', 'ident', 'start', 'stop', 'defsyntax', 'defsynfn', 'synfn', 'defspawner']
    \ }

let g:clojure_fuzzy_indent = 1
let g:clojure_fuzzy_indent_patterns = ['^def.*', '^with.*', 'specification', 'behavior', 'assertions', 'component', 'provided', 'start', 'stop', 'letfn', '-tx$', 'transact!', '^check.*', '^assert.*', 'concat', '.*Exception.*', '.*Error.*', 'trace\|debug\|info\|warn\|error\|fatal', '.*->>\?$', 'either', 'synfn', 'parse.*', 'spawn-*', 'load-data.*', '!$', '^do', 'into', '^test-.*', '\..*']
let g:clojure_fuzzy_indent_blacklist = []
let g:clojure_special_indent_words = 'defui,letfn,extend-type'
