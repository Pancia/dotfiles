if has("nvim")
    set runtimepath+=~/.config/nvim/plugged/conjure/
endif

augroup conjure_highlight
	autocmd!
	autocmd BufRead *.clj call conjure_highlight#syntax_match_references()
	autocmd BufRead *.cljc call conjure_highlight#syntax_match_references()
augroup END
