function! conjure_highlight#syntax_match_references()
  lua require("conjure-highlight.main").main()
endfunction

" Used by main.lua, couldn't figure out how to get &runtimepath as variable
function! conjure_highlight#clojure_highlight_filepath()
    return globpath(&runtimepath, 'autoload/conjure_highlight.clj')
endfunction
