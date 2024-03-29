if exists("b:loaded_zprint")
  finish
endif

let b:loaded_zprint = 1

if bufname('') =~ 'conjure-log-\d\+.cljc'
  finish
endif
if bufname('') =~ '.jar::'
  finish
endif
if !exists("g:zprint_should_apply")
  finish
endif

call zprint#apply()
