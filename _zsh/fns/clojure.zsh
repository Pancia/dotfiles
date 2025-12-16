function .lein { vim ~/.lein/profiles.clj }
function .prof { vim ~/.lein/profiles.clj }
function .profile { vim ~/.lein/profiles.clj }
function lc { lein clean }
function ltr { rlwrap lein test-refresh }
function ltrc { rlwrap lein do clean, test-refresh }
function lr { lein repl }
function lrc { lein do clean, repl"$@" }
function lr: { lein repl :connect }
function _with_out { (echo "$@"; command cat <&0) }
function lrw { (_with_out "$@") | lein repl }
function lrcw { (_with_out "$@") | lein do repl, clean }
function lr:w { (_with_out "$@") | lein repl :connect }
# ClojureScript
function cljs { planck "$@" }
