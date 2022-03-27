if exists("b:loaded_zprint")
    finish
endif

let b:loaded_zprint = 1

if bufname('') =~ 'conjure-log-\d\+.cljc'
    finish
endif

call zprint#apply()
