function! conjure_highlight#syntax_match_references()
  lua require("conjure-highlight.main").main()
endfunction

" Used by main.lua, couldn't figure out how to get &runtimepath as variable
function! conjure_highlight#clojure_highlight_filepath()
    return globpath(&runtimepath, 'autoload/conjure_highlight.clj')
endfunction

function! conjure_highlight#execute_syntax_command(cmd)
  try
    "echomsg a:cmd
    execute a:cmd
    let &syntax = &syntax
    "echomsg 'ch.vim/done'
  catch /.*/
    "echomsg 'ch.vim/catch'
    let b:clojure_syntax_keywords = {}
    let &syntax = &syntax
  endtry
endfunction

" Used by main.lua, using function directly had no effect
command! -nargs=1 ExecuteSyntaxCommand :call conjure_highlight#execute_syntax_command(<args>)
