let g:conjure#log#hud#width = "0.50"
let g:conjure#log#hud#height = "0.50"
let g:conjure#mapping#doc_word = "k"
let g:conjure#mapping#def_word = "gd"
let g:conjure#log#wrap = v:true

function! ResolveSymbol()
  call luaeval("require('conjure.client')['with-filetype']('clojure', require('conjure.eval')['eval-str'], { origin = 'dotfiles/clojuredocs', code = '`".expand("<cword>")."', ['on-result'] = function(sym) vim.api.nvim_command('call OpenClojureDocs(\"'..sym..'\")') end})")
endfunction

function! OpenClojureDocs(fqsym)
  echomsg "open clojure docs for: " . a:fqsym
  let [l:ns, l:sym] = split(a:fqsym, "/")
  if l:ns =~? 'clojure\..*'
    execute "!open 'https://clojuredocs.org/".l:ns."/".l:sym."'"
  else
    execute "!open 'https://www.google.com/search?q=".a:fqsym."'"
  endif
endfunction

nnoremap ,vd :call ResolveSymbol()<CR>
