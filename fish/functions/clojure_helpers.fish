# Clojure/Leiningen helper functions
function .lein --description 'Edit lein profile'
    vim ~/.lein/profiles.clj
end
alias .prof '.lein'
alias .profile '.lein'

function lc --description 'Leiningen clean' --wraps 'lein clean'
    lein clean
end

function ltr --description 'Leiningen test-refresh' --wraps 'lein test-refresh'
    rlwrap lein test-refresh
end

function ltrc --description 'Leiningen clean and test-refresh' --wraps 'lein test-refresh'
    rlwrap lein do clean, test-refresh
end

function lr --description 'Leiningen REPL' --wraps 'lein repl'
    lein repl
end

function lrc --description 'Leiningen clean and REPL' --wraps 'lein repl'
    lein do clean, repl $argv
end

function lr: --description 'Leiningen REPL connect' --wraps 'lein repl'
    lein repl :connect
end

function _with_out --description 'Echo args and cat stdin'
    echo $argv
    command cat
end

function lrw --description 'Leiningen REPL with input'
    _with_out $argv | lein repl
end

function lrcw --description 'Leiningen REPL clean with input'
    _with_out $argv | lein do repl, clean
end

function lr:w --description 'Leiningen REPL connect with input'
    _with_out $argv | lein repl :connect
end

function cljs --description 'ClojureScript REPL' --wraps planck
    planck $argv
end
