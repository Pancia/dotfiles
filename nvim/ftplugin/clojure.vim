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

" LANDMARK: ======== CONJURE =========

call COMMA_GROUP('v', '+ view / reveal')

call COMMA_CMD('vc', ":ConjureEval {:vlaaad.reveal/command '(clear-output)}", 'clear reveal output')

function! KaochaRunTest()
  call luaeval("require('conjure.client')['with-filetype']('clojure', require('conjure.eval')['eval-str'], { origin = 'dotfiles/run_specification', code = '(require (symbol \"kaocha.repl\"))(kaocha.repl/run '..require('conjure.extract')['form']({['root?'] = true})['content']..' (if (.exists (new java.io.File \"tests.local.edn\")) {:config-file \"tests.local.edn\"} {}))' })")
endfunction

call COMMA_GROUP('t', '+ tests')
call COMMA_CMD('tt', 'KaochaRunTest()')
nnoremap ,tt :call KaochaRunTest()<CR>

function! ShadowBuilds(A,L,P)
    return system("shadow-builds")
endfunction

function! ConnectToShadowBuild(input) abort
  execute ':ConjureShadowSelect '. a:input
endfunction

call COMMA_GROUP('c', '+ connections')
call COMMA_CMD('cc', 'ConnectToShadowBuild(input("ShadowBuild: ", "", "custom,ShadowBuilds"))', 'select shadow build to connect to')
call COMMA_CMD('cs', ':ConjureConnect 9000', 'connect conjure to shadow')
nnoremap <buffer><silent> ,cs :ConjureConnect 9000<CR>

call COMMA_GROUP('f', '+ filament / fulcro')
call COMMA_CMD('fg', 'RunCLJDevEval("start")')
call COMMA_CMD('fs', 'RunCLJDevEval("stop")')
call COMMA_CMD('fR', 'RunCLJDevEval("restart")')
call COMMA_CMD('fr', 'RunCLJDevEval("suspend-and-resume")')

nnoremap <buffer><expr> <esc> bufname('') =~ 'conjure-log-\d\+.cljc' ? ':normal ,lq<CR>' : '<esc>'

" LANDMARK: ======== LSP =========

nmap <silent> [l <Plug>(coc-diagnostic-prev)
nmap <silent> ]l <Plug>(coc-diagnostic-next)
nmap <silent> [k :CocPrev<cr>
nmap <silent> ]k :CocNext<cr>

function! s:show_documentation()
    if (index(['vim','help'], &filetype) >= 0)
        execute 'h '.expand('<cword>')
    elseif (coc#rpc#ready())
        call CocActionAsync('doHover')
    else
        execute '!' . &keywordprg . " " . expand('<cword>')
    endif
endfunction

nnoremap <silent> K :call <SID>show_documentation()<CR>

nmap <silent> gd <Plug>(coc-definition)
nmap <silent> gr <Plug>(coc-references)

nmap <leader>u <Plug>(coc-references)
nmap <leader>rn <Plug>(coc-rename)

function! s:Expand(exp) abort
    let l:result = expand(a:exp)
    return l:result ==# '' ? '' : "file://" . l:result
endfunction

function! LSP_exe_here(cmd, ...) abort
  call CocRequest('clojure-lsp', 'workspace/executeCommand', { 'command': a:cmd, 'arguments': [s:Expand('%:p'), line('.') - 1, col('.') - 1] + a:000 })
endfunction

call SEMICOLON_GROUP('sl', '+linting')
call SEMICOLON_CMD('slr', 'LSP_exe_here("resolve-macro-as", input("Resolve as?"), input("kondo config absolute path"))', 'resolve-as')

call SEMICOLON_GROUP('sr', '+refactorings')

call SEMICOLON_GROUP('srt', '+threading')
call SEMICOLON_CMD('srtf', 'LSP_exe_here("thread-first")', 'thread-first')
call SEMICOLON_CMD('srtt', 'LSP_exe_here("thread-last")', 'thread-last')
call SEMICOLON_CMD('srtF', 'LSP_exe_here("thread-first-all")', 'thread-first-all')
call SEMICOLON_CMD('srtT', 'LSP_exe_here("thread-last-all")', 'thread-last-all')
call SEMICOLON_CMD('srtu', 'LSP_exe_here("unwind-thread")', 'unwind-thread')
call SEMICOLON_CMD('srtU', 'LSP_exe_here("unwind-all")', 'unwind-all')

call SEMICOLON_GROUP('srr', '+requires')
call SEMICOLON_CMD('srra', 'LSP_exe_here("add-missing-libspec")', 'add-missing-libspec')

call SEMICOLON_GROUP('srl', '+let')
call SEMICOLON_CMD('srle', 'LSP_exe_here("expand-let")', 'expand-let')
call SEMICOLON_CMD('srlm', 'LSP_exe_here("move-to-let", input("Binding name: "))', 'move-to-let')
call SEMICOLON_CMD('srli', 'LSP_exe_here("introduce-let", input("Binding name: "))', 'introduce-let')
call SEMICOLON_CMD('su', '<Plug>(coc-references)', 'find usages')

" LANDMARK: ======== COPILOT =========

call COMMA_GROUP('g', '+ extra (copilot)')
call COMMA_GROUP('gc', 'copilot')
call COMMA_CMD('gcf', 'copilot#check_current_file()')
call COMMA_CMD('gcF', 'copilot#refresh_and_check_current_file()')
call COMMA_CMD('gcr', 'copilot#check_root_form()')
call COMMA_CMD('gcR', 'copilot#refresh_and_check_root_form()')

" LANDMARK: ======== FILAMENT ========

function! FilamentOpenDocForWord()
  call luaeval("require('conjure.client')['with-filetype']('clojure', require('conjure.eval')['eval-str'], { origin = 'dotfiles/clojuredocs', code = '(dev.filament.plugin.built-ins.wikidocs/doc! ".expand("<cword>").")', ['passive?'] = true})")
endfunction

call COMMA_CMD('fk', 'FilamentOpenDocForWord()')
